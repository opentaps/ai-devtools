require "openai"

class IssuesAiController < ApplicationController
  def api
    puts "[issues_ai] in /api handler"

    # validate the settings
    api_url = Setting.plugin_issues_ai['api_url']
    api_key = Setting.plugin_issues_ai['api_key']
    model = Setting.plugin_issues_ai['model']
    # those are optional but must be numbers
    temperature = Setting.plugin_issues_ai['temperature']
    max_tokens = Setting.plugin_issues_ai['max_tokens']

    if api_url.blank? || api_key.blank? || model.blank?
      render json: { error: 'Please configure the plugin settings: <a target="_blank" href="/settings/plugin/issues_ai">Configure</a>' }
      return
    end
    puts "[issues_ai] Checked required settings OK"

    if temperature.blank?
      temperature = 0.2
    else
      temperature = temperature.to_f
    end

    if max_tokens.blank?
      max_tokens = 2000
    else
      max_tokens = max_tokens.to_i
    end

    puts "[issues_ai] Checked optionsl settings OK"

    # read the POST data
    data = JSON.parse(request.body.read)
    puts "[issues_ai] Got data from POST #{data}"

    # subject and description can be on an 'issue' object
    # or given directly when no issue object is present
    subject = data['issue']['subject'] if data['issue']
    description = data['issue']['description'] if data['issue']
    subject = data['subject'] if subject.blank?
    description = data['description'] if description.blank?

    # validate
    if subject.blank? || description.blank?
      render json: { error: 'Please provide a subject and description' }
      return
    end

    # select a prompt that matches the tracker_id (this is a number) that represent the issue type in Redmine
    ticket_type_map = {
        1 => "bug",
        2 => "feature",
        3 => "support",
        4 => "longterm",
        5 => "unittests"
    }
    # get either tracker_id on issue or main request
    tracker_id = data['issue']['tracker_id'] if data['issue']
    tracker_id = data['tracker_id'] if tracker_id.blank?

    # if we have a tracker_id, use it to select the prompt
    prompt = ''
    if tracker_id
      key = ticket_type_map[tracker_id.to_i]
      prompt = Setting.plugin_issues_ai["prompt_#{key}"]
    end

    if prompt.blank?
      prompt = Setting.plugin_issues_ai["default_prompt"]
    end
    # hard code a default here
    if prompt.blank?
      prompt = 'Check how this ticket is worded and give useful feedback as to how it could be improved'
    end

    begin
      # call the openai API
      client = OpenAI::Client.new(
        access_token: api_key,
        uri_base: api_url,
      )

      # insert them into the prompt with labels:
      prompt = "#{prompt}\n\nSubject: #{subject}\nContent: #{description}\n\nAnalysis:"

      puts "[issues_ai] Calling the API at #{api_url} with model #{model}, temperature #{temperature}, max_tokens #{max_tokens}"
      response = client.chat(
        parameters: {
          model: model,
          temperature: temperature,
          max_tokens: max_tokens,
          messages: [{
            "role": "user",
            "content": prompt
          }]
        }
      )
      puts "[issues_ai] Got response"
      puts response

      # get the first choice
      analysis = response["choices"][0]["message"]["content"]
      puts "[issues_ai] Got analysis: #{analysis}"

      # The AI model may wrap the response in ```markdown ``` type quotes, remove them
      analysis = analysis.gsub(/^\s*```markdown/, '').gsub(/```\s*$/, '')

      # convert the markdown to html
      analysis_html = CommonMarker.render_html(analysis, :DEFAULT)
      render json: { analysis: analysis_html }
    rescue => e
      # print the error
      puts "Error: #{e.message}"
      render json: { error: e.message }
    end

  end

  # This is a GET handler that will be called when the user clicks the 'Queue Review' button
  def queue_review

    # get the 'commit' parameter
    commit = params[:commit]
    puts "[issues_ai] Queue Review for commit #{commit}"
    # get the changeset
    changeset = Changeset.find_by_revision(commit)
    if changeset.nil?
      # return an error
      render json: { error: 'Changeset not found' }
      return
    end
    # queue the review
    changeset.queue_code_review
    # redirect to the previous page
    redirect_to request.referer
  end

  # This is the ask, on GET we just render the view, on POST we also call the API and set @answer
  def ask
    @model = Setting.plugin_issues_ai['model']
    @title = "Ask the AI"
    project_id = params[:project] || 'graciousstyle'
    @project = find_project(project_id)

    if request.post? || request.get?
      @question = params[:question]
      @model = params[:model]
    end
    if @model.blank?
      @model = Setting.plugin_issues_ai['model']
    end

    is_form_update = params[:form_update_triggered_by] && !params[:form_update_triggered_by].blank?

    # check if this was a POST
    if request.post? && !is_form_update
      prompt = @question
      if prompt.blank?
        flash[:error] = "Question was empty"
        return
      end

      # the prompt can include placeholders for tickets like '#1234'
      # and wiki pages like '[[WikiPage]]'
      # We want to replace these with the actual content
      prompt = prompt.gsub(/#(\d+)/) do |match|
        issue = Issue.find_by_id($1)
        if issue
          "Subject: #{issue.subject}\nContent: #{issue.description}\n\n"
        else
          match
        end
      end

      prompt = prompt.gsub(/\[\[(.+)\]\]/) do |match|
        page = Wiki.find_page($1, :project => @project)
        if page
          "Document: #{page.title}\nContent: #{page.content.text}\n\n"
        else
          match
        end
      end

      begin
        # call the API
        client = OpenAI::Client.new(
          access_token: Setting.plugin_issues_ai['api_key'],
          uri_base: Setting.plugin_issues_ai['api_url'],
        )
        response = client.chat(
          parameters: {
            model: @model,
            messages: [{
              "role": "user",
              "content": prompt
            }]
          }
        )
        @answer = response["choices"][0]["message"]["content"]
      rescue => e
        # print the error
        puts "Error: #{e.message}"
        flash[:error] = e.message
      end

      # For testing return the prompt
      # @answer = prompt
    end

    respond_to do |format|
      format.html {render :action => 'ask', :layout => !request.xhr?}
      format.js
    end
  end

  def list_models
    # call the openai API
    client = OpenAI::Client.new(
      access_token: Setting.plugin_issues_ai['api_key'],
      uri_base: Setting.plugin_issues_ai['api_url'],
    )

    # get the models from the openAI api
    response = client.models.list
    @models = response['data'].map { |model| model['id'] }

    render json: { models: @models }
  end
end
