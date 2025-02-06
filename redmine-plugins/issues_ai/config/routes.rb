# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html
post 'issues_ai/api', to: 'issues_ai#api'
get 'issues_ai/queue_review', to: 'issues_ai#queue_review'

post 'issues_ai/code_review_settings', to: 'issues_ai#code_review_settings'
get 'issues_ai/code_review_settings', to: 'issues_ai#code_review_settings'

post 'issues_ai/code_review_commit', to: 'issues_ai#code_review_commit'
post 'issues_ai/save_code_review', to: 'issues_ai#save_code_review'

post 'issues_ai/ask', to: 'issues_ai#ask'
get 'issues_ai/ask', to: 'issues_ai#ask'

get 'issues_ai/list_models', to: 'issues_ai#list_models'
