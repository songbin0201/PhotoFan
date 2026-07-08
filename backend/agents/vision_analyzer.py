# agents/vision_analyzer.py
# 调用多模态模型分析相机帧，直接输出专业摄影建议

import json
import re
from openai import AsyncOpenAI
from models.request_models import SensorData, Suggestion
import config

_client = AsyncOpenAI(
    api_key=config.LLM_API_KEY,
    base_url=config.LLM_BASE_URL,
)

SYSTEM_PROMPT = """你是一个专业摄影师，擅长用最简洁的语言给出最实用的拍摄改善建议。"""

USER_PROMPT = """针对这张照片，给出 3 条具体的拍摄改善建议。

要求：
- 每条建议格式为"标题：具体操作说明"
- 建议要针对这张照片的实际问题，具体、可执行
- 涉及构图、光线、背景、角度、景深等方面

请只输出 JSON 数组，不要其他内容：
[
  {{"type": "composition", "text": "建议内容"}},
  {{"type": "lighting", "text": "建议内容"}},
  {{"type": "other", "text": "建议内容"}}
]

type 可选值：lighting / composition / focus / other"""


async def analyze(
    frame_base64: str,
    sensor_data: SensorData,
    active_types: list[str] | None = None,
) -> list[Suggestion]:
    """
    调用多模态模型分析照片，返回专业摄影建议。
    """
    prompt = USER_PROMPT

    try:
        print(f"[VisionAnalyzer] 开始调用 model={config.LLM_MODEL}")
        response = await _client.chat.completions.create(
            model=config.LLM_MODEL,
            max_tokens=512,
            temperature=0.7,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{frame_base64}"
                            }
                        },
                        {
                            "type": "text",
                            "text": prompt
                        }
                    ]
                }
            ]
        )

        raw = response.choices[0].message.content or ""
        print(f"[VisionAnalyzer] 模型返回: {raw[:300]}")
        return _parse_suggestions(raw)

    except Exception as e:
        print(f"[VisionAnalyzer] 模型调用失败: {e}")
        return []


def _parse_suggestions(raw: str) -> list[Suggestion]:
    """解析模型返回的 JSON 数组为 Suggestion 列表"""
    try:
        cleaned = re.sub(r"```(?:json)?|```", "", raw).strip()
        data = json.loads(cleaned)

        if not isinstance(data, list):
            data = [data]

        suggestions = []
        for item in data:
            if not isinstance(item, dict):
                continue
            suggestions.append(Suggestion(
                type=item.get("type", "other"),
                text=item.get("text", ""),
                priority=2,
            ))

        return suggestions

    except Exception as e:
        print(f"[VisionAnalyzer] JSON 解析失败: {e}\n原始内容: {raw[:200]}")
        return []
