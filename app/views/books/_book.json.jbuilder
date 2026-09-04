json.extract! book, :id, :user_prompt, :page_count, :text_context, :chatgpt_id, :user_id, :created_at, :updated_at
json.url book_url(book, format: :json)
