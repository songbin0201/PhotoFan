# agents/orchestrator.py
# Agent 主调度：接收请求 → 多模态分析 → 流式推送专业建议

import asyncio
import json
from typing import AsyncGenerator

from models.request_models import AnalyzeRequest, SuggestionPayload
from agents import vision_analyzer
import config


async def run(request: AnalyzeRequest) -> AsyncGenerator[str, None]:
    """
    主 Pipeline：
      1. 调用多模态模型分析画面，直接获取专业建议
      2. 过滤已在屏幕上的同类型建议
      3. 逐条 SSE 推送
    """

    # ── Step 1：多模态分析，直接获取建议列表 ──
    suggestions = await vision_analyzer.analyze(
        frame_base64=request.frame,
        sensor_data=request.sensor_data,
        active_types=request.active_suggestions,
    )

    # ── Step 2：过滤已在屏幕上的类型 ──
    active_types = set(request.active_suggestions)
    new_suggestions = [s for s in suggestions if s.type not in active_types]

    # 按优先级排序，最多推送 max_count 条
    new_suggestions.sort(key=lambda s: s.priority, reverse=True)
    new_suggestions = new_suggestions[:config.MAX_NEW_SUGGESTIONS]

    # ── Step 3：逐条推送 ──
    for suggestion in new_suggestions:
        payload = SuggestionPayload(
            id=suggestion.id,
            type=suggestion.type,
            text=suggestion.text,
            resolved=False,
        )
        yield _sse("suggestion", payload.model_dump())
        await asyncio.sleep(config.SSE_INTER_SUGGESTION_DELAY)

    # ── Step 4：结束信号 ──
    yield _sse("done", {})


def _sse(event: str, data: dict) -> str:
    """格式化单条 SSE 消息"""
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"
