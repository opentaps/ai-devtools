function selectModel(model, modalId, target) {
  console.log("selectModel", { model, modalId, target });
  // target can be a string or an element
  if (typeof target === "string") {
    target = $("#" + target);
  }
  target.val(model);
  hideModal("#" + modalId + " h3");
}

function openModelsModal(target, options) {
  // default modalId 'list_models'
  if (!options) options = {};
  const modalId = options.modalId || "list_models";
  // take the api_key and api_url from the options
  const data = {};
  if (options.api_key) {
    data.api_key = options.api_key;
  }
  if (options.api_url) {
    data.api_url = options.api_url;
  }
  if (options.provider) {
    data.provider = options.provider;
  }
  if (typeof target === "string") {
    target = $("#" + target);
  }
  if (!target) {
    console.error("No target found for openModelsModal");
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
      list.empty();
      if (data.models) {
        var models = data.models;
        for (var i = 0; i < models.length; i++) {
          const model = models[i];
          var dt = $("<dt>").append(
            $("<a>")
              .attr("href", "#")
              .attr("title", "Select")
              .text(model)
              .click(function () {
                selectModel(model, modalId, target);
                return false;
              }),
          );
          list.append(dt);
        }
      } else if (data.error) {
        list.append('<div class="error flash">Error: ' + data.error + "</div>");
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
