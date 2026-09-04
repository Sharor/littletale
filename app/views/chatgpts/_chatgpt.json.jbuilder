json.extract! chatgpt, :id, :prompt, :answer, :max_tokens, :reason_for_termination, :usage, :created_at, :updated_at
json.url chatgpt_url(chatgpt, format: :json)
