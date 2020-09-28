document.addEventListener("DOMContentLoaded", function (event) {
  safari.extension.dispatchMessage("CCInitialize");
});

document.addEventListener("contextmenu", function (event) {
  let selected = window.getSelection().toString();
  if(selected) {
    safari.extension.setContextMenuEventUserInfo(event, {
      "selected": selected,
      "url": window.location.href,
      "title": document.title
    })
  }
});

safari.self.addEventListener("message", messageHandler);

function messageHandler(message) {
    if(message.name === "CurrencyExchangeResult") {
        console.log(message)
    }
}
