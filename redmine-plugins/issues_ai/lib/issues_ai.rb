module IssuesAi
  class Hooks < Redmine::Hook::ViewListener
    # this is on the Create New Issue form
    render_on :view_issues_form_details_top, partial: "hooks/button_inject_new_issue"
    # customize changeset view of issues
    render_on :view_issues_history_changeset_bottom, partial: "hooks/changeset_bottom"
  end
end
