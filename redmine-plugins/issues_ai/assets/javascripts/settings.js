function add_provider() {
  const tbody = $("#providers");
  const row = add_text_input_row(tbody, "Provider Name", "[providers][name]", { placeholder: "OpenAI", help: "Identifier of the API provider", size: 30, required: true });
  // first row also need the remove button
  const remove_btn = $("<a>")
    .attr("href", "#")
    .text("Remove")
    .click(function () {
      remove_provider(this);
      return false;
    });
  row.find("td").append(remove_btn);
  add_text_input_row(tbody, "API Url", "[providers][url]", { placeholder: "https://api.openai.com/v1", help: "The base URL for any OpenAI compatible APIs", size: 30, required: true });
  add_text_input_row(tbody, "API Key", "[providers][key]", { help: "The API key for the provider", is_password: true, size: 80, required: true });
}

function add_input_row(tbody, label, name, input, opts) {
  const tr = $("<tr>");
  const th = $("<th>");
  if (opts.required) {
    th.html(label + ' <span class="required">* </span>');
  } else {
    th.html(label);
  }
  const td = $("<td>");

  td.append(input);
  if (opts.help) {
    const span = $("<span>").addClass("icon icon-help").attr("title", opts.help).html("&nbsp;");
    td.append(span);
  }
  tr.append(th);
  tr.append(td);
  tbody.append(tr);
  return tr;
}
function add_text_input_row(tbody, label, name, opts /*placeholder, help, is_password, is_number, min, step, required, length*/) {
  const input = $("<input>")
    .attr("type", opts.is_password ? "password" : opts.is_number ? "number" : "text")
    .attr("name", `settings${name}[]`)
    .attr("size", opts.length || 30);
  if (opts.placeholder) input.attr("placeholder", opts.placeholder);
  if (opts.required) input.attr("required", true);
  if (opts.min) input.attr("min", opts.min);
  if (opts.step) input.attr("step", opts.step);

  return add_input_row(tbody, label, name, input, opts);
}

function add_model() {
  const tbody = $("#models");
  // special case for the model selector
  const select = $("<select>").attr("name", "settings[models][provider][]").attr("required", true);
  for (var i = 0; i < ISSUES_AI_MODEL_PROVIDERS.length; i++) {
    const option = $("<option>").text(ISSUES_AI_MODEL_PROVIDERS[i]);
    select.append(option);
  }

  const row = add_input_row(tbody, "Model Provider", "[models][provider]", select, { required: true });
  // first row also need the remove button
  const remove_btn = $("<a>")
    .attr("href", "#")
    .text("Remove")
    .click(function () {
      remove_model(this);
      return false;
    });
  row.find("td").append(remove_btn);

  const row2 = add_text_input_row(tbody, "Model", "[models][name]", { required: true, size: 30 });
  // add the list model button
  const list_btn = $("<a>")
    .attr("href", "#")
    .text("Show available models")
    .click(function () {
      settings_open_models_modal(this);
      return false;
    });
  row2.find("td").append(list_btn);

  add_text_input_row(tbody, "Temperature", "[models][temperature]", { is_number: true, min: "0", step: "0.01", help: "Optional: change the model default temperature." });
  add_text_input_row(tbody, "Max Tokens", "[models][max_tokens]", { is_number: true, min: "0", help: "Optional: limit the amount of output tokens." });
}

function remove_rows(btn_el, row_count) {
  // the btn is on the provider name, we need to remove its row and the next row_count-1 rows
  const tr = $(btn_el).closest("tr");
  while (row_count > 1) {
    tr.next().remove();
    row_count--;
  }
  tr.remove();
}

function remove_provider(btn_el) {
  remove_rows(btn_el, 3);
}
function remove_model(btn_el) {
  remove_rows(btn_el, 4);
}

function toggle_settings(section) {
  $("#issues_ai_settings_menu li").removeClass("active");
  $("#issues_ai_settings_menu li." + section).addClass("active");
  $(".issues_ai_settings tbody").removeClass("active");
  $("." + section).addClass("active");
}

function settings_open_models_modal(btn_el) {
  // find the previous row
  const tr = $(btn_el).closest("tr");
  const prev_tr = tr.prev();
  const provider_select = prev_tr.find("select");
  const provider_name = provider_select.val();
  // call the openModelsModal function from the redmine plugin
  // with the target field and the provider name
  const target = tr.find("input");
  openModelsModal(target, { provider: provider_name });
}
