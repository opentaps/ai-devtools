$(document).ready(function () {
  const initAndPlaceButton = () => {
    // find the button
    var button = $("#issues_ai_btn");
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
