#require Project

module IssuesAiHelper
  def ask_project_select_tag(name='project', current_project)
    # find all the projects
    projects = Project.all
    options = projects.map { |p| [p.name, p.id] }
    select_tag(name, options_for_select(options, params[:project].to_s), :onchange => "updateIssuesAiAskFrom('#{escape_javascript update_ask_form_path(current_project)}', this)") if options.size > 1
  end

  # Returns the path for updating the form
  # with project as the current project
  def update_ask_form_path(project)
    options = {:format => 'js'}
    issues_ai_ask_path(options)
  end
end
