# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html
post 'issues_ai/api', to: 'issues_ai#api'
get 'issues_ai/queue_review', to: 'issues_ai#queue_review'

post 'issues_ai/ask', to: 'issues_ai#ask'
get 'issues_ai/ask', to: 'issues_ai#ask'

get 'issues_ai/list_models', to: 'issues_ai#list_models'
