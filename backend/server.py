# server.py
# FastAPI 入口：路由注册 + CORS + SSE 流式响应

import base64
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

from models.request_models import AnalyzeRequest
from agents import orchestrator
import config

app = FastAPI(
    title="PhotoFan Agent API",
    description="弹幕拍照 AI 助手后端服务",
    version="1.0.0",
)

# ── CORS（开发期间全放开，上线后收紧）──
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── 健康检查 ──
@app.get("/health")
async def health():
    return {"status": "ok", "model": config.DEEPSEEK_MODEL}


# ── 连通确认：轻量 SSE，不调用 AI ──
@app.post("/api/ping")
async def ping():
    """App 启动时调用，返回一条确认弹幕验证前后端联通"""
    import json

    async def _generate():
        payload = {
            "id": "ping-ack",
            "type": "other",
            "text": "已抓取当前帧",
            "resolved": False,
        }
        yield f"event: suggestion\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"
        yield "event: done\ndata: {}\n\n"

    return StreamingResponse(
        _generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


# ── 核心：帧分析 + SSE 流式推送 ──
@app.post("/api/analyze")
async def analyze(request: AnalyzeRequest):

    # 校验帧大小（防止超大图片拖慢响应）
    try:
        frame_bytes = base64.b64decode(request.frame)
    except Exception:
        raise HTTPException(status_code=400, detail="frame 不是有效的 Base64")

    if len(frame_bytes) > config.MAX_FRAME_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"帧图像超过 {config.MAX_FRAME_BYTES // 1024}KB 限制"
        )

    return StreamingResponse(
        orchestrator.run(request),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",      # 禁止 Nginx 缓冲，保证实时推送
            "Connection": "keep-alive",
        },
    )


# ── 本地启动入口 ──
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "server:app",
        host=config.HOST,
        port=config.PORT,
        reload=True,        # 开发模式热重载
        log_level="info",
    )
