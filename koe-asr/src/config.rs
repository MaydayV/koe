/// Configuration for an ASR session.
#[derive(Debug, Clone)]
pub struct AsrConfig {
    /// ASR provider: "doubao" or "qwen"
    pub provider: String,
    /// WebSocket endpoint URL
    pub url: String,
    /// X-Api-App-Key (App ID from Volcengine console)
    pub app_key: String,
    /// X-Api-Access-Key (Access Token from Volcengine console)
    pub access_key: String,
    /// X-Api-Resource-Id (e.g. "volc.bigasr.sauc.duration")
    pub resource_id: String,
    /// Audio sample rate in Hz (default: 16000)
    pub sample_rate_hz: u32,
    /// Connection timeout in milliseconds (default: 3000)
    pub connect_timeout_ms: u64,
    /// Timeout waiting for final ASR result after finish signal (default: 5000)
    pub final_wait_timeout_ms: u64,
    /// Enable DDC (disfluency removal / smoothing)
    pub enable_ddc: bool,
    /// Enable ITN (inverse text normalization)
    pub enable_itn: bool,
    /// Enable automatic punctuation
    pub enable_punc: bool,
    /// Enable two-pass recognition (streaming + non-streaming re-recognition)
    pub enable_nonstream: bool,
    /// Hotwords for improved recognition accuracy
    pub hotwords: Vec<String>,
    /// Qwen realtime endpoint URL
    pub qwen_base_url: String,
    /// Qwen API key (DashScope/Bailian)
    pub qwen_api_key: String,
    /// Qwen realtime ASR model id
    pub qwen_model: String,
    /// Qwen recognition language (e.g. "zh", "en")
    pub qwen_language: String,
    /// Enable server-side VAD for Qwen realtime ASR
    pub qwen_enable_vad: bool,
    /// Qwen VAD threshold (recommended 0.0)
    pub qwen_vad_threshold: f64,
    /// Qwen VAD silence threshold in milliseconds (recommended 400)
    pub qwen_vad_silence_duration_ms: u64,
}

impl Default for AsrConfig {
    fn default() -> Self {
        Self {
            provider: "doubao".into(),
            url: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async".into(),
            app_key: String::new(),
            access_key: String::new(),
            resource_id: "volc.seedasr.sauc.duration".into(),
            sample_rate_hz: 16000,
            connect_timeout_ms: 3000,
            final_wait_timeout_ms: 5000,
            enable_ddc: true,
            enable_itn: true,
            enable_punc: true,
            enable_nonstream: true,
            hotwords: Vec::new(),
            qwen_base_url: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime".into(),
            qwen_api_key: String::new(),
            qwen_model: "qwen3-asr-flash-realtime".into(),
            qwen_language: "zh".into(),
            qwen_enable_vad: true,
            qwen_vad_threshold: 0.0,
            qwen_vad_silence_duration_ms: 400,
        }
    }
}
