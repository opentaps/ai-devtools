require_dependency File.expand_path('../lib/issues_ai', __FILE__)

Redmine::Plugin.register :issues_ai do
  name 'AI Issues plugin'
  author 'Jeremy Wickersheimer'
  description 'Use AI to review Bug reports and Feature requests before posting them on Redmine'
  version '0.0.1'
  url 'https://github.com/opentaps/ai-devtools/redmine-plugins/issues_ai'
  settings default: {'empty' => true}, partial: 'settings/issues_ai_settings'
  # Include JavaScript/CSS assets
  Rails.application.config.assets.precompile += %w( issues_ai.js )
end
