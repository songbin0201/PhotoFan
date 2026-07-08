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

SYSTEM_PROMPT = """你是一位获奖无数的专业摄影指导大师，正在通过手机屏幕实时辅导用户拍照。
你的目标是帮用户拍出媲美专业摄影师的作品，而不仅仅是"没问题"的照片。

你的风格：
- 像大师在旁边轻声提醒，温和但精准
- 给出具体可执行的动作指令，不说废话
- 每条建议控制在 12-20 个中文字符以内（弹幕显示空间有限）
- 建议文案必须引用屏幕上的视觉标记，让用户看到文字就知道看屏幕哪里
  例如："移到屏幕黄圈位置"、"朝箭头方向移动手机"、"对齐闪烁的虚线框"
- 绝对不用摄影术语（三分法、负空间、引导线等）"""

USER_PROMPT = """观察这张实时取景画面，结合传感器数据：
{sensor_context}

当前屏幕上已有的建议类型：{active_types}
（请不要重复这些类型的建议）

请从以下维度分析，给出 1-3 条最有价值的改善建议：

1. 光线运用（lighting）：侧光/逆光/伦勃朗光/黄金时段/曝光调整
2. 构图技法（composition）：三分法/引导线/框架构图/对称/负空间/视角高低
3. 焦点与景深（focus）：焦点选择/前景虚化/背景简化
4. 稳定与清晰（stability）：防抖技巧/快门速度
5. 场景特定（scene）：根据识别到的场景给出针对性建议
   - 人像：眼神光/姿态/背景干净
   - 风景：前景层次/天空比例/地平线水平
   - 美食：俯拍角度/摆盘留白/自然光方向
   - 街拍：等待决定性瞬间/背景简洁
   - 建筑：垂直线校正/对称感
6. 创意提升（creative）：不寻常的角度/色彩对比/情绪表达

重要：text 必须是用户能立刻执行的身体/手机动作，不要用摄影术语！
例如：
- 错误："使用三分法构图" ← 用户不懂
- 正确："手机右移一点，人物靠左竖线" ← 用户马上能做

请只输出 JSON 数组，不要解释或 markdown：
[
  {{
    "type": "类型",
    "text": "动作指令12-18字",
    "priority": 1到3,
    "action": {{"control": "控件", "direction": "方向"}},
    "guide": {{"type": "引导类型", "direction": "方向", "position": "位置"}}
  }}
]

字段说明：
- type：lighting / composition / focus / stability / tilt / other
- priority：1=锦上添花 2=明显改善 3=关键问题
- text：用户可立刻执行的身体/手机动作指令，12-18字，不用术语
- action：手机参数调节（不涉及则省略）
  - control：exposure / iso / white_balance / focus
  - direction：increase / decrease / auto
- guide：屏幕视觉引导（每条建议都必须有）
  - type：arrow（方向箭头）/ grid_point（网格交叉点高亮）/ target_zone（目标区域）/ level（水平仪）
  - direction：left / right / up / down / back / forward（箭头方向或移动方向）
  - position：top_left / top_right / bottom_left / bottom_right / center（引导显示位置）"""


async def analyze(
    frame_base64: str,
    sensor_data: SensorData,
    active_types: list[str] | None = None,
) -> list[Suggestion]:
    """
    调用多模态模型分析帧图像，直接返回专业摄影建议列表。
    """
    sensor_context = (
        f"设备倾斜：X轴 {sensor_data.tilt_x:.1f}°，Y轴 {sensor_data.tilt_y:.1f}°\n"
        f"本地亮度估值：{sensor_data.brightness:.2f}（0最暗，1最亮）\n"
        f"对焦状态：{'正在对焦中' if sensor_data.is_focusing else '对焦稳定'}"
    )

    active_display = "、".join(active_types) if active_types else "无"

    prompt = USER_PROMPT.format(
        sensor_context=sensor_context,
        active_types=active_display,
    )

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
            action = None
            if "action" in item and isinstance(item["action"], dict):
                from models.request_models import SuggestionAction
                action = SuggestionAction(
                    control=item["action"].get("control", ""),
                    direction=item["action"].get("direction", ""),
                )
            guide = None
            if "guide" in item and isinstance(item["guide"], dict):
                from models.request_models import SuggestionGuide
                guide = SuggestionGuide(
                    type=item["guide"].get("type", ""),
                    direction=item["guide"].get("direction", ""),
                    position=item["guide"].get("position", "center"),
                )
            suggestions.append(Suggestion(
                type=item.get("type", "other"),
                text=item.get("text", ""),
                priority=int(item.get("priority", 2)),
                action=action,
                guide=guide,
            ))

        return suggestions

    except Exception as e:
        print(f"[VisionAnalyzer] JSON 解析失败: {e}\n原始内容: {raw[:200]}")
        return []
