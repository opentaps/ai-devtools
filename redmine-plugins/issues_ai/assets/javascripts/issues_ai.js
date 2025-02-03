$(document).ready(function () {
  const initAndPlaceButton = () => {
    // find the button
    var button = $("#issues_ai_btn");
    if (button.length === 0) {
      // button not found, do nothing
      return;
    }

    // check the button type from data-eval
    var btnType = button.attr("data-issues_ai-type");
    //  now move it accordingly. if we have buttons in other pages we can tweak the placement like this
    if (btnType === "issue") {
      // find the element with id issue_description_and_toolbar and move the button after it
      $("#issue_description_and_toolbar").after(button);
    }

    button.on("click", function () {
      var formData = $("#issue-form").serializeArray();
      // button type defines the context
      var jsonData = { context: btnType };

      // Convert form data to nested JSON
      formData.forEach(function (field) {
        var nameParts = field.name.split(/[\[\]]+/).filter((part) => part !== "");
        var current = jsonData;
        nameParts.forEach(function (part, index) {
          if (index === nameParts.length - 1) {
            current[part] = field.value;
          } else {
            current[part] = current[part] || {};
            current = current[part];
          }
        });
      });

      // clear previous results
      $("#issues_ai_result").remove();

      // disable the button while processing
      button.prop("disabled", true);
      // and set the loading css class
      button.addClass("loading");

      // Send to API
      $.ajax({
        //url: "http://127.0.0.1:5000/ai/review_ticket", // Replace with your API endpoint
        url: "/issues_ai/api",
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify(jsonData),
        headers: {
          "X-CSRF-Token": $('meta[name="csrf-token"]').attr("content"),
        },
        success: function (response) {
          $("#issues_ai_result").remove();
          if (response.error) {
            button.after('<div id="issues_ai_result" class="flash error">' + response.error + "</div>");
          } else {
            button.after('<div id="issues_ai_result" class="flash issues_ai_results">' + response.analysis + "</div>");
          }
          // re-enable the button
          button.prop("disabled", false);
          button.removeClass("loading");
        },
        error: function (xhr) {
          $("#issues_ai_result").remove();
          if (xhr.status === 400 && xhr.responseJSON && xhr.responseJSON.error) {
            button.after('<div id="issues_ai_result" class="flash error">' + xhr.responseJSON.error + "</div>");
          } else {
            button.after('<div id="issues_ai_result" class="flash error">An unexpected error occurred.</div>');
          }
          // re-enable the button
          button.prop("disabled", false);
          button.removeClass("loading");
        },
      });
    });
  };

  // do it onload
  initAndPlaceButton();

  // must also do that when the form is reloaded
  $(document).ajaxComplete(function () {
    initAndPlaceButton();
  });
});

function updateIssuesAiAskFrom(url, el) {
  $("#all_attributes input, #all_attributes textarea, #all_attributes select").each(function () {
    $(this).data("valuebeforeupdate", $(this).val());
  });
  if (el) {
    $("#form_update_triggered_by").val($(el).attr("id"));
  }
  return $.ajax({
    url: url,
    type: "post",
    data: $("#ask-form").serialize(),
  });
}

function replaceIssuesAiAskFormWith(html) {
  var replacement = $(html);
  $("#all_attributes input, #all_attributes textarea, #all_attributes select").each(function () {
    var object_id = $(this).attr("id");
    if (object_id && $(this).data("valuebeforeupdate") != $(this).val()) {
      replacement.find("#" + object_id).val($(this).val());
    }
  });
  $("#all_attributes").empty();
  $("#all_attributes").prepend(replacement);
}

$(document).ready(function () {
  var button = $("#submit_ask_ai_btn");
  if (button.length === 0) {
    // button not found, do nothing
    return;
  }
  var form = button.closest("form");
  if (form.length === 0) {
    // form not found, do nothing
    return;
  }

  form.on("submit", function () {
    // disable the button while processing
    button.prop("disabled", true);
    // and set the loading css class
    button.addClass("loading");
    // clear previous results if any
    $("#ask_ai_results").remove();
  });
});
