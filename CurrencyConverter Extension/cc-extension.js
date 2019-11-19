document.addEventListener("DOMContentLoaded", function (event) {
  safari.extension.dispatchMessage("CCInitialize");
});

document.addEventListener("contextmenu", function (event) {
  console.log(event)
  if (event.srcElement && isImgUrl(event.srcElement.src)) {
    //console.log(event.srcElement.src)
    //We can start handle picture...
    //alert(event.srcElement.src)
    safari.extension.setContextMenuEventUserInfo(event, { "imageSrc": event.srcElement.src });
  }

  let selected = window.getSelection().toString();
  if(selected) {
    safari.extension.setContextMenuEventUserInfo(event, {"selected": selected})
  }
});

safari.self.addEventListener("message", messageHandler);

function messageHandler(message) {
    if(message.name === "CurrencyExchangeResult") {
        console.log(message)
    }
}



function isImgUrl(url) {
  if(!isValidUrl(url)) {
    return false;
  }
  let pure = getPathFromUrl(url)
  return (pure.match(/\.(jpeg|jpg|gif|png)$/) != null);
}

function getPathFromUrl(url) {
  return url.split("?")[0];
}

const isValidUrl = (string) => {
  try {
    new URL(string);
    return true;
  } catch (_) {
    return false;
  }
}
