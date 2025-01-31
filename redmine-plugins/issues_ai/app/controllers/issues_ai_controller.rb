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
end
