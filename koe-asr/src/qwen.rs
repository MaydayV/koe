use crate::config::AsrConfig;
use crate::error::{AsrError, Result};
use crate::event::AsrEvent;
use crate::provider::AsrProvider;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine;
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tokio::time::{timeout, Duration};
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{connect_async, MaybeTlsStream, WebSocketStream};
use uuid::Uuid;

type WsStream = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

/// Qwen realtime ASR provider using Bailian/DashScope WebSocket API.
pub struct QwenRealtimeWsProvider {
    ws: Option<WsStream>,
    use_vad: bool,
    has_connected_event: bool,
}

impl QwenRealtimeWsProvider {
    pub fn new() -> Self {
        Self {
            ws: None,
            use_vad: true,
            has_connected_event: false,
        }
    }

    fn next_event_id() -> String {
        format!("event_{}", Uuid::new_v4().simple())
    }

    async fn send_json(ws: &mut WsStream, payload: Value) -> Result<()> {
        let text = serde_json::to_string(&payload)
            .map_err(|e| AsrError::Protocol(format!("serialize JSON: {e}")))?;
        ws.send(Message::Text(text.into()))
            .await
            .map_err(|e| AsrError::Connection(format!("send event: {e}")))
    }

    fn parse_server_event(&mut self, value: Value) -> Option<AsrEvent> {
        let event_type = value
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        match event_type {
            "session.created" | "session.updated" => {
                if self.has_connected_event {
                    None
                } else {
                    self.has_connected_event = true;
                    Some(AsrEvent::Connected)
                }
            }
            "conversation.item.input_audio_transcription.text" => {
                let text = value
                    .get("text")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default();
                let stash = value
                    .get("stash")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default();
                Some(AsrEvent::Interim(format!("{text}{stash}")))
            }
            "conversation.item.input_audio_transcription.completed" => {
                let final_text = value
                    .get("transcript")
                    .and_then(|v| v.as_str())
                    .or_else(|| value.get("text").and_then(|v| v.as_str()))
                    .unwrap_or_default()
                    .to_string();
                Some(AsrEvent::Final(final_text))
            }
            "conversation.item.input_audio_transcription.failed" => {
                let message = value
                    .get("error")
                    .and_then(|e| e.get("message"))
                    .and_then(|v| v.as_str())
                    .or_else(|| value.get("message").and_then(|v| v.as_str()))
                    .unwrap_or("Qwen ASR transcription failed")
                    .to_string();
                Some(AsrEvent::Error(message))
            }
            "error" => {
                let message = value
                    .get("error")
                    .and_then(|e| e.get("message"))
                    .and_then(|v| v.as_str())
                    .or_else(|| value.get("message").and_then(|v| v.as_str()))
                    .unwrap_or("unknown Qwen ASR error")
                    .to_string();
                Some(AsrEvent::Error(message))
            }
            "session.finished" => Some(AsrEvent::Closed),
            _ => None,
        }
    }
}

impl Default for QwenRealtimeWsProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl AsrProvider for QwenRealtimeWsProvider {
    async fn connect(&mut self, config: &AsrConfig) -> Result<()> {
        if config.qwen_api_key.trim().is_empty() {
            return Err(AsrError::Connection(
                "qwen_api_key is empty; set asr.qwen_api_key in config".into(),
            ));
        }

        let connect_timeout = Duration::from_millis(config.connect_timeout_ms);
        let mut request = config
            .qwen_base_url
            .as_str()
            .into_client_request()
            .map_err(|e| AsrError::Connection(format!("invalid URL: {e}")))?;

        let headers = request.headers_mut();
        headers.insert(
            "Authorization",
            format!("Bearer {}", config.qwen_api_key)
                .parse()
                .map_err(|_| AsrError::Connection("invalid qwen_api_key".into()))?,
        );
        headers.insert(
            "OpenAI-Beta",
            "realtime=v1"
                .parse()
                .map_err(|_| AsrError::Connection("invalid OpenAI-Beta header".into()))?,
        );

        let (ws_stream, _) = timeout(connect_timeout, async {
            connect_async(request)
                .await
                .map_err(|e| AsrError::Connection(e.to_string()))
        })
        .await
        .map_err(|_| AsrError::Connection("connection timed out".into()))??;

        self.use_vad = config.qwen_enable_vad;
        self.has_connected_event = false;
        self.ws = Some(ws_stream);

        let sample_rate = if config.sample_rate_hz == 8000 || config.sample_rate_hz == 16000 {
            config.sample_rate_hz
        } else {
            16000
        };

        let session_payload = if self.use_vad {
            json!({
                "event_id": Self::next_event_id(),
                "type": "session.update",
                "session": {
                    "input_audio_format": "pcm",
                    "sample_rate": sample_rate,
                    "input_audio_transcription": {
                        "model": config.qwen_model,
                        "language": config.qwen_language,
                    },
                    "turn_detection": {
                        "type": "server_vad",
                        "threshold": config.qwen_vad_threshold,
                        "silence_duration_ms": config.qwen_vad_silence_duration_ms,
                    }
                }
            })
        } else {
            json!({
                "event_id": Self::next_event_id(),
                "type": "session.update",
                "session": {
                    "input_audio_format": "pcm",
                    "sample_rate": sample_rate,
                    "input_audio_transcription": {
                        "model": config.qwen_model,
                        "language": config.qwen_language,
                    },
                    "turn_detection": Value::Null
                }
            })
        };

        if let Some(ref mut ws) = self.ws {
            Self::send_json(ws, session_payload).await?;
        }

        Ok(())
    }

    async fn send_audio(&mut self, frame: &[u8]) -> Result<()> {
        let ws = self
            .ws
            .as_mut()
            .ok_or_else(|| AsrError::Connection("WebSocket not connected".into()))?;

        let payload = json!({
            "event_id": Self::next_event_id(),
            "type": "input_audio_buffer.append",
            "audio": BASE64_STANDARD.encode(frame),
        });
        Self::send_json(ws, payload).await
    }

    async fn finish_input(&mut self) -> Result<()> {
        let ws = self
            .ws
            .as_mut()
            .ok_or_else(|| AsrError::Connection("WebSocket not connected".into()))?;

        if !self.use_vad {
            Self::send_json(
                ws,
                json!({
                    "event_id": Self::next_event_id(),
                    "type": "input_audio_buffer.commit",
                }),
            )
            .await?;
        }

        Self::send_json(
            ws,
            json!({
                "event_id": Self::next_event_id(),
                "type": "session.finish",
            }),
        )
        .await
    }

    async fn next_event(&mut self) -> Result<AsrEvent> {
        loop {
            let next_msg = {
                let ws = self
                    .ws
                    .as_mut()
                    .ok_or_else(|| AsrError::Connection("WebSocket not connected".into()))?;
                ws.next().await
            };

            match next_msg {
                Some(Ok(Message::Text(text))) => {
                    let value: Value = serde_json::from_str(&text)
                        .map_err(|e| AsrError::Protocol(format!("parse JSON event: {e}")))?;
                    if let Some(event) = self.parse_server_event(value) {
                        return Ok(event);
                    }
                }
                Some(Ok(Message::Binary(bin))) => {
                    let value: Value = serde_json::from_slice(&bin)
                        .map_err(|e| AsrError::Protocol(format!("parse JSON event: {e}")))?;
                    if let Some(event) = self.parse_server_event(value) {
                        return Ok(event);
                    }
                }
                Some(Ok(Message::Ping(payload))) => {
                    let ws = self
                        .ws
                        .as_mut()
                        .ok_or_else(|| AsrError::Connection("WebSocket not connected".into()))?;
                    ws.send(Message::Pong(payload))
                        .await
                        .map_err(|e| AsrError::Connection(format!("send pong: {e}")))?;
                }
                Some(Ok(Message::Pong(_))) => {}
                Some(Ok(Message::Close(_))) => return Ok(AsrEvent::Closed),
                Some(Ok(Message::Frame(_))) => {}
                Some(Err(e)) => return Err(AsrError::Connection(format!("recv event: {e}"))),
                None => return Ok(AsrEvent::Closed),
            }
        }
    }

    async fn close(&mut self) -> Result<()> {
        if let Some(ref mut ws) = self.ws {
            let _ = ws.send(Message::Close(None)).await;
        }
        self.ws = None;
        Ok(())
    }
}
