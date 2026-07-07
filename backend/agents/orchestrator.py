# agents/orchestrator.py
# Agent 主调度：接收请求 → 并行分析 → 流式推送 SSE 事件

import asyncio
import json
from typing import AsyncGenerator

from models.request_models import (
    AnalyzeRequest, SuggestionPayload, ResolvePayload
)
from agents import vision_analyzer, suggestion_planner, resolve_detector
import config


async def run(request: AnalyzeRequest) -> AsyncGenerator[str, None]:
    """
    主 Pipeline，返回 SSE 格式的异步生成器。
    事件顺序：
      1. resolve 事件（先告知哪些建议已解决 → 立刻变绿）
      2. suggestion 事件（新建议，错开间隔逐条推送）
      3. done 事件
    """

    # ── Step 1：视觉分析（调用 DeepSeek）──
    vision_result = await vision_analyzer.analyze(
        frame_base64=request.frame,
        sensor_data=request.sensor_data,
    )

    # ── Step 2：判断哪些已有建议可以 resolve ──
    # iOS 端传来的 active_suggestions 是 type 列表
    # 这里我们构造 id 映射（实际项目中 iOS 应传 [{id, type}] 列表，
    # 当前简化为 type 即 id，与 iOS 端 mock 保持一致）
    active_items = [{"id": t, "type": t} for t in request.active_suggestions]

    resolved_ids = resolve_detector.find_resolved(
        active_items=active_items,
        vision_result=vision_result,
        sensor_data=request.sensor_data,
    )

    # 先推送所有 resolve 事件（让弹幕立刻变绿）
    for rid in resolved_ids:
        payload = ResolvePayload(id=rid, resolved=True)
        yield _sse("resolve", payload.model_dump())

    # ── Step 3：生成新建议 ──
    # 过滤掉已在屏幕上的类型
    new_suggestions = suggestion_planner.plan(
        vision_result=vision_result,
        sensor_data=request.sensor_data,
        active_types=request.active_suggestions,
        max_count=config.MAX_NEW_SUGGESTIONS,
    )

    # 逐条推送，错开间隔，让弹幕依次飘出
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
