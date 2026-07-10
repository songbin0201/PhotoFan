# config.py
# 环境变量 + 模型参数配置

from dotenv import load_dotenv
import os

load_dotenv()

# ── LLM（豆包 Doubao-Seed-1.6-vision，支持多模态）──
LLM_API_KEY  = os.getenv("LLM_API_KEY", "")
LLM_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3/"
LLM_MODEL    = os.getenv("LLM_MODEL", "ep-20260710091325-v6x5z")

# ── 服务 ──
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", 8000))

# ── 业务参数 ──
MAX_FRAME_BYTES      = 5_000_000   # 上传图片最大 5MB
MAX_NEW_SUGGESTIONS  = 3         # 每次最多推送几条新建议
SSE_INTER_SUGGESTION_DELAY = 0.3 # 相邻两条建议的推送间隔（秒）
