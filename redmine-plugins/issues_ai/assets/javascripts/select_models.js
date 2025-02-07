function selectModel(model, modalId, targetId) {
  var target = $("#" + targetId);
  target.val(model);
  hideModal("#" + modalId + " h3");
}

function openModelsModal(targetId, options) {
  // default modalId 'list_models'
  if (!options) options = {};
  var modalId = options.modalId || "list_models";
  // take the api_key and api_url from the options
  var data = {};
  if (options.api_key) {
    data.api_key = options.api_key;
  }
  if (options.api_url) {
    data.api_url = options.api_url;
  }

  var list = $("#" + modalId + " dl");
  list.empty();
  list.append("<dt>Loading...</dt>");
  // load the JSON list from /issues_ai/list_models
  // pass the api_key and api_url as parameters
  $.ajax({
    url: "/issues_ai/list_models",
    type: "GET",
    contentType: "application/json",
    headers: {
      "X-CSRF-Token": $('meta[name="csrf-token"]').attr("content"),
    },
    data: data,
    success: function (data) {
      var models = data.models;
      list.empty();
      for (var i = 0; i < models.length; i++) {
        var model = models[i];
        var dt = $("<dt>").append(
          $("<a>")
            .attr("href", "#")
            .attr("title", "Select")
            .attr("onclick", 'selectModel("' + model + '", "' + modalId + '", "' + targetId + '"); return false;')
            .text(model),
        );
        list.append(dt);
      }
      showModal(modalId, "500px");
    },
    error: function (xhr) {
      list.empty();
      list.append('<div class="error flash">Error: ' + xhr.statusText + ". Please check the API URL and Keys are correct. Note that not all providers support listing the available models via the API.</dt>");

      showModal(modalId, "500px");
    },
  });
}
