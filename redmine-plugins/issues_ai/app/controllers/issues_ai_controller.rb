require "openai"

class IssuesAiController < ApplicationController
  include IssuesAiTools
  helper :repositories

  def api
    puts "[issues_ai] in /api handler"

    # validate the settings, must have a default model
    model = get_default_model()
    if model.blank?
      render json: { error: 'Please configure the plugin settings: <a target="_blank" href="/settings/plugin/issues_ai">Configure</a>' }
      return
    end
    puts "[issues_ai] Checked required settings OK"

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
      client = get_client(model)
      parameters = get_chat_params(model)
      parameters[:messages] = [{role: :user, content: prompt }]

      # insert them into the prompt with labels:
      prompt = "#{prompt}\n\nSubject: #{subject}\nContent: #{description}\n\nAnalysis:"

      puts "[issues_ai] Calling the API with model #{model}, parameters #{parameters}"
      response = client.chat(
        parameters: parameters
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

  # Page to change the settings of the code review for a repository
  def code_review_settings

    repository_id = params[:repository_id]
    unless repository_id.blank?
      @repository = Repository.find_by_id(repository_id)
      if @repository.nil?
        flash[:error] = "Repository not found"
        return
      end

      @prompt = @repository.code_review_prompt
      @prompt_multi = @repository.code_review_prompt_multi
    end

    # check if this was a POST
    if request.post?
      if repository_id.blank?
        flash[:error] = "Repository ID is required"
        return
      end
      @prompt = params[:prompt]
      if @prompt.blank?
        flash[:error] = "Prompt is required"
        return
      end
      @prompt_multi = params[:prompt_multi]
      if @prompt_multi.blank?
        flash[:error] = "Prompt for Multiple commits is required"
        return
      end
      @repository.code_review_prompt = @prompt
      @repository.code_review_prompt_multi = @prompt_multi
    end
  end

  # Perform the Code review for a given commit hash
  def code_review_commit
    @back = params[:back_url]
    # if we came from an Issue page
    @issue_id = params[:issue_id]
    # ge the changeset
    commit_hash = params[:commit_hash]
    puts "Got commit hash: #{commit_hash}"
    if commit_hash.nil?
      flash[:error] = "Commit hash is required"
      return
    end
    # split the commit hash at comma
    commit_hashes = commit_hash.split(',')

    # validate them by fetching all the changesets
    # and they must be all from the same repository
    @changesets = []
    repository = nil
    commit_hashes.each do |commit_hash|
      changeset = Changeset.find_by_revision(commit_hash)
      if changeset.nil?
        flash[:error] = "Changeset #{commit_hash} not found"
        return
      end
      if repository.nil?
        repository = changeset.repository
      elsif repository != changeset.repository
        flash[:error] = "Changesets are not from the same repository"
        return
      end
      @changesets << changeset
    end

    if repository.nil?
      flash[:error] = "Repository not found for this changeset"
      return
    end

    prompt = repository.code_review_prompt
    # for analyzing multiple commits, we need to adapt the prompt
    if @changesets.length > 1
      prompt = repository.code_review_prompt_multi
    end

    if prompt.blank?
      flash[:error] = "Code review prompt not found for this repository"
      return
    end

    @combined_diff = nil
    begin
      # extract the Commit template from the prompt: it is the part between <commit> and </commit> tags
      commit_tpl = prompt.match(/<commit>(.*)<\/commit>/m)[1]
      if commit_tpl.nil?
        flash[:error] = "Commit template not found in the prompt"
        return
      end

      # remove the commit template from the prompt but keep the </commit> marker
      prompt = prompt.gsub(/<commit>.*<\/commit>/m, '</commit>')

      @changesets.each do |changeset|
        parsed = parse_commit(changeset)
        if parsed.nil?
          flash[:error] = "Changeset diff not found"
          return
        end
        # insert the values into the template
        tpl = commit_tpl
        puts "Populating commit template #{tpl} with #{parsed}"
        tpl = tpl.gsub(/{hash}/, parsed[:hash])
        tpl = tpl.gsub(/{author}/, parsed[:author])
        tpl = tpl.gsub(/{date}/, parsed[:date])
        tpl = tpl.gsub(/{subject}/, parsed[:subject])
        tpl = tpl.gsub(/{body}/, parsed[:body])
        tpl = tpl.gsub(/{diff}/, parsed[:diff])
        # insert the commit template into the prompt at the </commit> marker
        prompt = prompt.gsub(/<\/commit>/, tpl + '</commit>')
        puts "Built prompt: #{prompt}"

        if @combined_diff.nil?
          @combined_diff = parsed[:diff]
        else
          @combined_diff += "\n\n" + parsed[:diff]
        end
      end
      # cleanup the extra </commit> marker by replacing the ending </commit></commit> with just </commit>
      prompt = prompt.gsub(/<\/commit><\/commit>/, '</commit>')
      if @combined_diff.nil?
        flash[:error] = "No changeset data found"
        return
      end

      puts "[issues_ai] Code Review Prompt: #{prompt}"

    rescue => e
      flash[:error] = "Error getting changeset data: #{e.message}"
      puts e
      puts e.backtrace
      return
    end

    # validate the settings
    model = get_code_review_model()
    error = nil
    if model.blank?
      error = 'Please configure the plugin settings: <a target="_blank" href="/settings/plugin/issues_ai">Configure</a>'
    end

    unless error
      begin
        # call the openai API
        client = get_client(model)

        puts "[issues_ai] Code Review model #{model}"
        parameters = get_chat_params(model)
        parameters[:messages] = [{role: :user, content: prompt }]
        response = client.chat(parameters: parameters)
        puts "[issues_ai] Code Review Got response"
        # get the first choice
        @review = response.dig("choices", 0, "message", "content")
        puts "[issues_ai] Code Review Got result: #{@review}"
      rescue => e
        # print the error
        error = "Error running code review prompt: #{e.message}"
        puts error
        puts e
        puts e.backtrace
      end
    end

    if error
      flash[:error] = error
    else
      begin
        # if we only had a single changeset and
        # if the changeset had no review saved, saved it now automatically
        if @changesets.length == 1
          @changeset = @changesets[0]
          if !@changeset.has_code_review_results?
            @changeset.save_code_review_results(@review)
          else
            @previous_review = @changeset.code_review_results
          end
        end
      rescue => e
        puts "Ignoring Error: #{e.message}"
      end
    end
  end

  def save_code_review
    review = params[:review]
    back = params[:back_url]

    # giving an issue_id saves it as a note
    issue_id = params[:issue_id]
    # else a commit_hash is required to save it as a file
    commit = params[:commit_hash]

    # validation
    if review.blank?
      flash[:error] = "Review is required"
      return
    end

    if issue_id.blank? && commit.blank?
      flash[:error] = "Issue ID or Commit hash is required"
      return
    end

    # the save logic
    if !commit.blank?
      puts "[issues_ai] Save new Review for commit #{commit}"

      changeset = Changeset.find_by_revision(commit)
      if changeset.nil?
        flash[:error] = "Changeset not found"
        return
      end

      changeset.save_code_review_results(review)
    else
      puts "[issues_ai] Save new Review for issue #{issue_id}"
      issue = Issue.find_by_id(issue_id)
      if issue.nil?
        flash[:error] = "Issue not found"
        return
      end
      # save the review as a note
      journal = issue.init_journal(User.current)
      # prefix the review with a title
      review = "# AI Code Review:\n\n#{review}"
      journal.notes = review
      issue.save!
      # in this case always redirect to the issue
      redirect_to issue
      return
    end
    redirect_to back
  end

  # This is a GET handler that will be called when the user clicks the 'Queue Review' button
  def queue_review

    # get the 'commit_hash' parameter
    commit = params[:commit_hash]
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
    @model = ''
    @title = "Ask the AI"
    project_id = params[:project] || 'graciousstyle'
    @project = find_project(project_id)

    if request.post? || request.get?
      @question = params[:question]
      @model = params[:model]
    end
    if @model.blank?
      @model = get_default_model()
    end
    if @model.blank?
      flash[:error] = "Please configure the plugin settings: <a target='_blank' href='/settings/plugin/issues_ai'>Configure</a>"
      return
    end
    # for tool calling check if we have a configured model
    @tool_model = Setting.plugin_issues_ai['tool_model']
    if @tool_model.blank?
      @tool_model = @model
    end

    is_form_update = params[:form_update_triggered_by] && !params[:form_update_triggered_by].blank?

    # check if this was a POST
    if request.post? && !is_form_update
      prompt = @question
      if prompt.blank?
        flash[:error] = "Question was empty"
        return
      end

      messages = [{
        role: :user,
        content: prompt
      }]
      prompt_changed = false

      # run the prompt and check for function calls
      begin
        client = get_client(@tool_model)
        parameters = get_chat_params(@tool_model)
        parameters[:tools] = TOOLS
        parameters[:messages] = messages
        # call the API
        response = client.chat(parameters: parameters)
        msg = response.dig("choices", 0, "message")
        tool_calls = msg.dig("tool_calls")
        # usefull for debugging and to show the user what was called
        @functions_called = []
        if tool_calls
          puts "Response tool calls count: #{tool_calls.length}"
          # For a subsequent message with the role "tool", OpenAI requires
          # the preceding message to have a tool_calls argument.
          messages << msg
          # indicate we need to repeat the user prompt at the end
          prompt_changed = true
          # then add the tool call results to the messages
          tool_calls.each do |tool_call|
            puts " - tool call: #{tool_call}"
            tool_call_id = tool_call.dig("id")
            function_name = tool_call.dig("function", "name")
            function_args = JSON.parse(
              tool_call.dig("function", "arguments"),
              { symbolize_names: true },
            )

            puts " > Try to call tool function_name: #{function_name} with #{function_args}"
            function_response = invoke_the_right_tool(function_name, function_args)
            @functions_called << {
              function_name: function_name,
              arguments: function_args,
              response: function_response
            }

            if function_response
              # do no print the results as this could be a lot of text
              # but check the length:

              puts " = Called function #{function_name} successfully with response length: #{function_response.length}"
            else
              puts " = Failed to call function #{function_name}"
              function_response = "Failed to call function #{function_name}."
            end

            # always add the tool call result to the messages
            messages << {
              tool_call_id: tool_call_id,
              role: :tool,
              name: function_name,
              content: function_response
            }
          end
        else
          puts "No tool calls found"
        end
      rescue => e
        # print the error
        puts "Error running prompt with tools: #{e.message}"
        puts e
        puts e.backtrace
        flash[:error] = e.message
        return
      end


      # the prompt can include placeholders for tickets like '#1234'
      # and wiki pages like '[[WikiPage]]'
      # We want to replace these with the actual content
      prompt = prompt.gsub(/#(\d+)/) do |match|
        issue = Issue.find_by_id($1)
        if issue
          prompt_changed = true
          format_issue_for_llm(issue)
        else
          match
        end
      end

      prompt = prompt.gsub(/\[\[(.+)\]\]/) do |match|
        page = Wiki.find_page($1, :project => @project)
        if page
          prompt_changed = true
          "Document: #{page.title}\nContent: #{page.content.text}\n\n"
        else
          match
        end
      end

      begin
        # this is the final prompt
        if @tool_model != @model
          # check if we are changing provider
          m1 = get_modeL_settings(@tool_model)
          m2 = get_modeL_settings(@model)
          if m1[:provider] != m2[:provider]
            puts "Changing provider from #{m1[:provider]} to #{m2[:provider]}"
            client = get_client(@model)
            # when changing the model provider, we cannot have
            # the messages with the tools as they all use different
            # syntax and have dfferent expectations in the format ....
            # instead we restart the conversation with the results
            # we got from the tools injected as context in the original prompt
            if @functions_called.length > 0
              messages = []
              preamble = "The following context was given by the function calling tools according to the user prompt:\n"
              @functions_called.each do |f|
                preamble += "\n#{f[:response]}\n"
              end
              preamble += "\n----------------\n"
              messages << {
                role: :assistant,
                content: preamble
              }
              # force re-adding the prompt later
              prompt_changed = true
            end
          end
        end

        # append the prompt to the previous messages that inluded the tool calls
        # and results
        if prompt_changed
          messages << {
            role: :user,
            content: prompt
          }
        end
        parameters = get_chat_params(@model)
        parameters[:messages] = messages
        response = client.chat(parameters: parameters)
        @answer = response["choices"][0]["message"]["content"]
      rescue Faraday::Error => e
        puts "Faraday Error: #{e}"
        if e.response
          # could have a JSON with error=>message=>"the error"
          begin
            puts "Error response: #{e.response_body}"
            # sometimes response_body is an array
            res = e.response_body
            if res.is_a?(Array)
              res = res[0]
            end
            error = res.dig("error", "message")
            if error
              flash[:error] = error
              return
            end
          rescue => e2
            # ignore this
            puts "Error parsing error response: #{e2}"
            puts e2.backtrace
          end
        else
          puts "No response in error"
        end
        flash[:error] = e.message
      rescue => e
        # print the error
        puts "Error: #{e.message}"
        puts e
        puts e.backtrace
        flash[:error] = e.message
      end
    end

    puts "Answer: #{@answer}"

    respond_to do |format|
      format.html {render :action => 'ask', :layout => !request.xhr?}
      format.js
    end
  end

  def list_models
    # allow the api key and url or the provider name to be given as parameters
    api_key = params[:api_key]
    api_url = params[:api_url]
    provider = params[:provider]

    unless provider.blank?
      # find it in the setttings, where provider = setttings[providers][name]
      idx = Setting.plugin_issues_ai['providers']['name'].find_index { |p| p == provider }
      if idx
        api_key = Setting.plugin_issues_ai['providers']['key'][idx]
        api_url = Setting.plugin_issues_ai['providers']['url'][idx]
      else
        render json: { error: "Provider #{provider} not found" }
        return
      end
    else
      if api_key.blank? || api_url.blank?
        render json: { error: 'Please provide the Provider Name or the API URL and Key' }
        return
      end
    end

    # cache the models for 1 hour given the parameters as Key
    cache_key = "list_models_#{api_key}_#{api_url}"
    @models = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      # call the openai API
      client = OpenAI::Client.new(
        access_token: api_key,
        uri_base: api_url,
      )

      # get the models from the openAI api
      response = client.models.list
      # extract the model ids and sort them
      models = response['data'].map { |model| model['id'] }
      models.sort!
    end

    render json: { models: @models }
  end


  private

  def get_default_model()
    model = Setting.plugin_issues_ai['model']
    if defined?(model) && model.present?
      return model
    end
    # else use the first model in the list
    model = Setting.plugin_issues_ai.dig('models', 'name', 0)
    return model || ""
  end

  def get_code_review_model()
    model = Setting.plugin_issues_ai['code_review_model']
    if defined?(model) && model.present?
      return model
    end
    get_default_model()
  end

  def find_provider_idx(model_string)
    # the model given as a string <provider>:<model>
    # split it into provider and model
    provider, model = model_string.split(':')
    # find the provider in the setttings, where provider = setttings[providers][name]
    Setting.plugin_issues_ai['providers']['name'].find_index { |p| p == provider }
  end

  def find_model_idx(model_string)
    # the model given as a string <provider>:<model>
    # split it into provider and model (note: the model itself can contain ':')
    provider, model = model_string.split(':', 2)
    puts "[find_model_idx] Finding model #{model} with provider #{provider}"
    # find the model that matches both the name and the provider (in case there are multiple of each)
    indexes = Setting.plugin_issues_ai['models']['name'].each_index.select { |i| Setting.plugin_issues_ai['models']['name'][i] == model && Setting.plugin_issues_ai['models']['provider'][i] == provider }

    # if empty
    if indexes.length == 0
      raise "Model not found #{model_string}"
    end
    idx = indexes[0]
    puts "[find_model_idx] Found model at index #{idx}: #{Setting.plugin_issues_ai['models']['provider'][idx]} / #{Setting.plugin_issues_ai['models']['name'][idx]}"
    return idx
  end


  def get_client(model_string)
    # find the provider in the setttings, where provider = setttings[providers][name]
    idx = find_provider_idx(model_string)
    unless idx
      raise "Provider not found for #{model_string}"
    end

    provider = Setting.plugin_issues_ai['providers']['name'][idx]
    api_key = Setting.plugin_issues_ai['providers']['key'][idx]
    api_url = Setting.plugin_issues_ai['providers']['url'][idx]

    puts "[get_client] Using provider #{provider} with url #{api_url}"

    OpenAI::Client.new(
      access_token: api_key,
      uri_base: api_url,
    )
  end

  def get_modeL_settings(model_string)
    puts "[get_modeL_settings] Finding model #{model_string}"
    # find all the settings for the model, in a hash with name, provider, temperature, max_tokens
    idx = find_model_idx(model_string)
    unless idx
      raise "Model #{model_string} not found"
    end

    {
      model: Setting.plugin_issues_ai['models']['name'][idx],
      provider: Setting.plugin_issues_ai['models']['provider'][idx],
      temperature: Setting.plugin_issues_ai['models']['temperature'][idx],
      max_tokens: Setting.plugin_issues_ai['models']['max_tokens'][idx]
    }
  end


  def get_chat_params(model_string)
    model_settings = get_modeL_settings(model_string)
    params = {
      model: model_settings[:model]
    }

    # temperature and max_tokens are optional
    if defined?(model_settings[:temperature]) && model_settings[:temperature].present?
      params[:temperature] = model_settings[:temperature]
    end
    if defined?(model_settings[:max_tokens]) && model_settings[:max_tokens].present?
      params[:max_tokens] = model_settings[:max_tokens]
    end

    puts "[get_chat_params] Using model #{params}"

    return params
  end
end
