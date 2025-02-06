$(document).ready(function () {
  var layout = document.getElementById("layout");
  var button = document.getElementById("toggle_layout");
  var diff_box = document.getElementById("diff_box");
  var review_box = document.getElementById("review_box");
  const obs_size = () => {
    // sync the height of the review box with the diff box
    review_box.style.height = diff_box.style.height;
  };
  var boxes_obs = new ResizeObserver(obs_size);

  $(button).on("click", function () {
    if (layout.style.flexDirection == "row") {
      boxes_obs.unobserve(diff_box);
      layout.style.flexDirection = "column";
      button.innerHTML = "View Side by Side";
      diff_box.style.height = "45vh";
      diff_box.style.width = "auto";
      diff_box.style.resize = "vertical";
      review_box.style.height = "auto";
      review_box.style.width = "auto";
    } else {
      layout.style.flexDirection = "row";
      button.innerHTML = "View Stacked";
      diff_box.style.height = "75vh";
      diff_box.style.width = "60%";
      diff_box.style.resize = "both";
      review_box.style.height = diff_box.style.height;
      boxes_obs.observe(diff_box);
    }
  });
});
