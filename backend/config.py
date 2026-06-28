# config.py
# 环境变量 + 模型参数配置

from dotenv import load_dotenv
import os

load_dotenv()

# ── DeepSeek ──
DEEPSEEK_API_KEY  = os.getenv("DEEPSEEK_API_KEY", "")
DEEPSEEK_BASE_URL = "https://api.deepseek.com"
DEEPSEEK_MODEL    = "deepseek-chat"   # DeepSeek-V3，支持图像理解

# ── 服务 ──
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", 8000))

# ── 业务参数 ──
MAX_FRAME_BYTES      = 500_000   # 上传帧最大 500KB
MAX_NEW_SUGGESTIONS  = 3         # 每次最多推送几条新建议
SSE_INTER_SUGGESTION_DELAY = 0.3 # 相邻两条建议的推送间隔（秒）
