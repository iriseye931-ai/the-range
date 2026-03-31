#!/bin/bash
# PreToolUse hook: scans Write/Edit content for secrets before writing to disk.
# Exit 2 = block the tool call. Exit 0 = allow.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Only scan Write and Edit tools
if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then
    exit 0
fi

# Extract the content being written
CONTENT=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
inp = d.get('tool_input', {})
# Write has 'content', Edit has 'new_string'
text = inp.get('content', '') or inp.get('new_string', '')
print(text[:8000])
" 2>/dev/null)

FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
inp = d.get('tool_input', {})
print(inp.get('file_path', inp.get('file_path', '')))
" 2>/dev/null)

# Skip scanning .env.example, test fixtures, and this hook itself
case "$FILE_PATH" in
    *.env.example|*/fixtures/*|*/test-data/*|*/pre-write-scan.sh)
        exit 0
        ;;
esac

# Run pattern scan
FINDINGS=$(echo "$CONTENT" | python3 -c "
import sys, re

content = sys.stdin.read()
findings = []

patterns = [
    (r'sk-[A-Za-z0-9]{20,}', 'OpenAI/Anthropic API key (sk-)'),
    (r'ANTHROPIC_API_KEY\s*=\s*[\"'\'']\S+[\"'\'']', 'Anthropic API key assignment'),
    (r'-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----', 'Private key'),
    (r'ghp_[A-Za-z0-9]{36}', 'GitHub personal access token'),
    (r'gho_[A-Za-z0-9]{36}', 'GitHub OAuth token'),
    (r'github_pat_[A-Za-z0-9_]{82}', 'GitHub fine-grained token'),
    (r'AKIA[0-9A-Z]{16}', 'AWS Access Key ID'),
    (r'(?i)(password|passwd|pwd)\s*=\s*[\"'\''][^\"'\'']{4,}[\"'\'']', 'Hardcoded password'),
    (r'(?i)(secret|api_key|apikey|auth_token)\s*=\s*[\"'\''][A-Za-z0-9+/=_\-]{8,}[\"'\'']', 'Hardcoded secret/key'),
    (r'teamirs-dev-key-\S+', 'OpenViking dev key'),
    (r'uk_[A-Za-z0-9]{20,}', 'AMP user key'),
    (r'Bearer\s+[A-Za-z0-9\-_\.]{20,}(?![\"'\''].*placeholder)', 'Bearer token in code'),
]

for pattern, label in patterns:
    matches = re.findall(pattern, content[:8000])
    if matches:
        # Skip obvious placeholders
        for m in matches:
            m_str = str(m)
            if any(x in m_str.lower() for x in ['placeholder', 'your_key', 'example', 'xxxx', 'sk-...', 'sk-proj-...']):
                continue
            findings.append(f'{label}: ...{m_str[-12:]}')
            break

if findings:
    print('\n'.join(findings[:5]))
" 2>/dev/null)

if [ -n "$FINDINGS" ]; then
    echo "SECRET DETECTED — write blocked. Findings:"
    echo "$FINDINGS"
    echo ""
    echo "Remove secrets before writing. Use env vars or ~/.env (not committed)."
    exit 2
fi

exit 0
