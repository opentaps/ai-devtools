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

  def project_repositories_select_tag(name='repository_id')
    # find all the projects
    projects = Project.all
    # For each project, find the repositories and generate the options for the select tag with the label as "Project Name - Repository Name" and the value as the repository id
    options = projects.map do |p|
      p.repositories.map do |r|
        ["#{p.name} - #{r.name}", r.id]
      end
    end
    # need to flatten the array
    options = options.flatten(1)
    # remove the empty repositories
    options = options.reject { |o| o[0].nil? }
    # add a blank option first
    options = [['- Choose a Repository -', '']] + options
    select_tag(name, options_for_select(options, params[:repository_id].to_s)) if options.size > 1
  end
end
