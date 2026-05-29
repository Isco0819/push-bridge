# Push Bridge — jq sanitization rules.
# Walks every string value in the input JSON and redacts known secret patterns.
# Edit this file to add patterns; restart of the hook is not required.

def redact:
  . |
  gsub("sk-ant-[A-Za-z0-9_-]+"; "REDACTED_ANTHROPIC_KEY") |
  gsub("sk-proj-[A-Za-z0-9_-]+"; "REDACTED_OPENAI_KEY") |
  gsub("sk-[A-Za-z0-9]{32,}"; "REDACTED_OPENAI_KEY") |
  gsub("gsk_[A-Za-z0-9]{40,}"; "REDACTED_GROQ_KEY") |
  gsub("ghp_[A-Za-z0-9]{30,}"; "REDACTED_GH_TOKEN") |
  gsub("ghs_[A-Za-z0-9]{30,}"; "REDACTED_GH_TOKEN") |
  gsub("github_pat_[A-Za-z0-9_]{60,}"; "REDACTED_GH_PAT") |
  gsub("AKIA[0-9A-Z]{16}"; "REDACTED_AWS_KEY") |
  gsub("ASIA[0-9A-Z]{16}"; "REDACTED_AWS_STS_KEY") |
  gsub("AIzaSy[A-Za-z0-9_-]{33}"; "REDACTED_GCP_KEY") |
  gsub("xox[abprs]-[A-Za-z0-9-]+"; "REDACTED_SLACK_TOKEN") |
  gsub("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"; "REDACTED_JWT") |
  gsub("(?i)(?<k>password|passwd|secret|api[_-]?key|token|bearer)(?<sep>[\"' ]*[:=][\"' ]*)[A-Za-z0-9_\\-\\.]{20,}"; "\(.k)\(.sep)REDACTED") |
  gsub("postgres(?:ql)?://[^@]+@[^/]+/[^\\s\"']+"; "REDACTED_PG_URL") |
  gsub("mongodb(?:\\+srv)?://[^@]+@[^/]+/[^\\s\"']*"; "REDACTED_MONGO_URL") |
  gsub("redis://[^@]*@[^/]+"; "REDACTED_REDIS_URL");

walk(if type == "string" then redact else . end)
