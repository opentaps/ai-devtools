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

  def model_select_tag(name='model')
    default_model = Setting.plugin_issues_ai['model']

    selected_value = params[name].to_s if params[name].present?
    selected_value = default_model if selected_value.blank?

    options = []
    if defined?(default_model)
      options << default_model
      options << ['----', '']
    end

    models = Setting.plugin_issues_ai['models']
    if defined?(models)
      providers = models['provider']
      if defined?(providers)
        providers.each_with_index do |provider, idx|
          lbl = "#{provider}:#{models['name'][idx]}"
          options << lbl
        end
      end
    end

    if options.size == 0
      "No models configured, please configure a model in the plugin settings"
    else
      select_tag(name, options_for_select(options, selected_value))
    end
  end

end
