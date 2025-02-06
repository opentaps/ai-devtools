require "openai"

class IssuesAiController < ApplicationController
  include IssuesAiTools
  helper :repositories

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
      @repository.code_review_prompt = @prompt
    end
  end

  # Perform the Code review for a given commit hash
  def code_review_commit
    @back = params[:back_url]
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

      # for analyzing multiple commits, we need to adapt the prompt
      if @changesets.length > 1
        prompt += "\nNote that this is a combined analysis of multiple commits. Please provide a more detailed review of the combined changes."
      end

      puts "[issues_ai] Code Review Prompt: #{prompt}"

    rescue => e
      flash[:error] = "Error getting changeset data: #{e.message}"
      puts e
      puts e.backtrace
      return
    end

    # validate the settings
    api_url = Setting.plugin_issues_ai['api_url']
    api_key = Setting.plugin_issues_ai['api_key']
    model = Setting.plugin_issues_ai['model']
    error = nil
    if api_url.blank? || api_key.blank? || model.blank?
      error = 'Please configure the plugin settings: <a target="_blank" href="/settings/plugin/issues_ai">Configure</a>'
    end

    unless error
      begin
        # call the openai API
        client = OpenAI::Client.new(
          access_token: api_key,
          uri_base: api_url,
        )

        puts "[issues_ai] Code Review Calling the API at #{api_url} with model #{model}"
        response = client.chat(
          parameters: {
            model: model,
            messages: [{
              "role": "user",
              "content": prompt
            }]
          }
        )
        puts "[issues_ai] Code Review Got response"
        # get the first choice
        @review = response.dig("choices", 0, "message", "content")
        puts "[issues_ai] Code Review Got result: #{@review}"
      rescue => e
        # print the error
        error = "Error running prompt with tools: #{e.message}"
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
    commit = params[:commit_hash]
    review = params[:review]
    back = params[:back_url]

    puts "[issues_ai] Save new Review for commit #{commit}"

    changeset = Changeset.find_by_revision(commit)
    if changeset.nil?
      flash[:error] = "Changeset not found"
      return
    end

    changeset.save_code_review_results(review)
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

      # init the client
      # run the prompt and check for function calls
      begin
        # call the API
        client = OpenAI::Client.new(
          access_token: Setting.plugin_issues_ai['api_key'],
          uri_base: Setting.plugin_issues_ai['api_url'],
        )
      rescue => e
        # print the error
        puts "Error creating the client: #{e.message}"
        puts e.backtrace
        flash[:error] = e.message
        return
      end

      messages = [{
        role: :user,
        content: prompt
      }]

      # run the prompt and check for function calls
      begin
        # call the API
        response = client.chat(
          parameters: {
            model: @tool_model,
            messages: messages,
            tools: TOOLS
          }
        )
        msg = response.dig("choices", 0, "message")
        tool_calls = msg.dig("tool_calls")
        puts "Response tool calls: #{tool_calls}"
        if tool_calls
          tool_calls.each do |tool_call|
            tool_call_id = tool_call.dig("id")
            function_name = tool_call.dig("function", "name")
            function_args = JSON.parse(
              tool_call.dig("function", "arguments"),
              { symbolize_names: true },
            )
            puts "Try to call tool function_name: #{function_name} with #{function_args}"
            function_response = invoke_the_right_tool(function_name, function_args)

            if function_response
              # do no print the results as this could be a lot of text
              # but check the length:

              puts "Called function #{function_name} successfully with response length: #{function_response.length}"
              # For a subsequent message with the role "tool", OpenAI requires
              # the preceding message to have a tool_calls argument.
              messages << msg

              messages << {
                tool_call_id: tool_call_id,
                role: :tool,
                name: function_name,
                content: function_response
              }
            end
          end
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
          format_issue_for_llm(issue)
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

      # append the prompt to the previous messages that inluded the tool calls
      # and results
      messages << {
        role: :user,
        content: prompt
      }

      begin
        response = client.chat(
          parameters: {
            model: @model,
            messages: messages
          }
        )
        @answer = response["choices"][0]["message"]["content"]
      rescue Faraday::Error => e
        puts "Faraday Error: #{e}"
        if e.response
          # could have a JSON with error=>message=>"the error"
          begin
            puts "Error response: #{e.response_body}"
            error = e.response_body.dig("error", "message")
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
