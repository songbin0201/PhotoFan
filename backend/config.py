# config.py
# 环境变量 + 模型参数配置

from dotenv import load_dotenv
import os

load_dotenv()

# ── LLM（Gemini via OpenAI-compatible API）──
LLM_API_KEY  = os.getenv("LLM_API_KEY", "")
LLM_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai/"
LLM_MODEL    = "gemini-2.0-flash"

# ── 服务 ──
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", 8000))

# ── 业务参数 ──
MAX_FRAME_BYTES      = 500_000   # 上传帧最大 500KB
MAX_NEW_SUGGESTIONS  = 3         # 每次最多推送几条新建议
SSE_INTER_SUGGESTION_DELAY = 0.3 # 相邻两条建议的推送间隔（秒）
