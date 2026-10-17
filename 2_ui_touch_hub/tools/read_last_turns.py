import json
import sys

sys.stdout.reconfigure(encoding='utf-8')
transcript_path = r'C:\Users\胡珂\.gemini\antigravity\brain\44b86f26-de1b-41bc-bc6c-1efd36abce37\.system_generated\logs\transcript.jsonl'

user_msgs = []
with open(transcript_path, 'r', encoding='utf-8') as f:
    for line in f:
        try:
            d = json.loads(line)
            if d.get('type') == 'USER_INPUT':
                user_msgs.append((d.get('step_index'), d.get('content')))
        except Exception:
            pass

for idx, text in user_msgs[-12:]:
    print(f"=== Step {idx} ===")
    print(text)
