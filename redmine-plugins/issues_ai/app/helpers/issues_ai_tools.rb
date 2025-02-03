# The functions to help with the AI tools
module IssuesAiTools
  # Retreive tickets for the AI prompts.
  # optional arguments:
  #  - max_age_days: filter out tickets that are more than max_age_days old
  #  - status: filter out tickets that are not in the given status, can be 'all', 'open' or 'closed'
  #  - tracker: filter out tickets that are not of the given tracker, can be 'all' or the name of the tracker
  #     like 'bug', 'feature', 'support', 'long_term', 'test'
  #  - limit: limit the number of tickets returned
  def tool_get_tickets(max_age_days: 0, status: '', tracker:'', limit: 0)

    puts "tool_get_tickets: max_age_days: #{max_age_days}, status: #{status}, limit: #{limit}"

    # build the conditions
    res = Issue.all
    has_conditions = false
    # order ID in descending order
    res = res.order(id: :desc)

    # convert the max_age_days to a Date:
    if max_age_days != 0
      res = res.where("created_on > ?", max_age_days.to_i.days.ago)
      has_conditions = true
    end

    # filter out the status
    if status != '' && status != 'all'
      # map the 'open' or 'closed' to the actual status ids:
      # 1: new, 2: in progress, 3: resolved, 4: feedback, 5: closed
      # 6: rejected, 7: need review, 8: reviewed, 9: ready to deploy
      # 10: deployed
      if status == 'open'
        res = res.where("status_id IN (?)", [1, 2, 4, 7, 8, 9])
        has_conditions = true
      elsif status == 'closed'
        res = res.where("status_id IN (?)", [3, 5, 6, 10])
        has_conditions = true
      end
    end

    # filter out the tracker
    if tracker != '' && tracker != 'all'
      # find the tracker id
      # 1: bug, 2: feature, 3: support, 4: long_term, 5: test
      tracker_id = case tracker
        when 'bug'
          1
        when 'feature'
          2
        when 'support'
          3
        when 'long_term'
          4
        when 'test'
          5
      else
        nil
      end

      unless tracker_id.nil?
        res = res.where("tracker_id = ?", tracker_id)
        has_conditions = true
      end
    end

    # limit the number of tickets
    if limit != 0
      res = res.limit(limit)
      has_conditions = true
    end

    # if there are no conditions, avoid returning all the tickets
    # as it could be a lot of data
    # instead look at the last 50
    if !has_conditions
      res = res.limit(50)
    end

    puts "tool_get_tickets: found #{res.count} res: #{res}"

    # format the tickets for the LLM
    # for now we need
    # - Ticket ID: id
    # - Title: subject
    # - Description: description
    # - Type: tracker
    # - Status: status
    # - Created on: created_on
    # - Assigned to: assigned_to
    # Format in text:
    strings = res.map { |r| format_issue_for_llm(r) }
    if strings.empty?
      return "No tickets found."
    else
      return strings.join("\n")
    end

  end

  # schema for the get_tickets function
  TOOL_GET_TICKETS_SCHEMA = {
    type: :function,
    function: {
      name: "get_tickets",
      description: "Get tickets from the Redmine API",
      parameters: {
        type: :object,
        properties: {
          max_age_days: {
            type: :number,
            description: "The maximum age of the tickets in days"
          },
          status: {
            type: :string,
            description: "Only return tickets with this status",
            enum: %w[all open closed],
          },
          tracker: {
            type: :string,
            description: "Only return tickets with this tracker",
            enum: %w[all bug feature support long_term test],
          },
          limit: {
            type: :number,
            description: "The maximum number of tickets to get"
          },
        },
        required: [],
        additionalProperties: false,
      },
    }
  }

  # convert a Redmine issue to a format that the LLM can understand
  def format_issue_for_llm(r)
    "### Ticket ID: ##{r.id}\n  Title: #{r.subject}\n  Description: #{r.description}\n  Type: #{r.tracker.nil? ? 'N/A' : r.tracker.name}\n  Status: #{r.status.nil? ? 'N/A' : r.status.name}\n  Created on: #{r.created_on}\n  #{r.assigned_to.nil? ? 'Not assigned' : 'Assigned to: ' + r.assigned_to.name}\n\n"
  end

  # Invoke the right tool based on the function_name
  def invoke_the_right_tool(function_name, function_args)
    case function_name
    when "get_tickets"
      tool_get_tickets(**function_args)
    else
      puts "Unknown tool function_name: #{function_name}"
      nil
    end
  end

  # Use this for the `tools` argument in the openAI request
  TOOLS = [TOOL_GET_TICKETS_SCHEMA]
end
