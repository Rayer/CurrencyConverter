# Currency Converter Safari Plugin

這個Plugin的主要目的是，當macOS 10.15 Catalina釋出的時候順帶把Dashboard拔掉了，Dashboard裡面有個好用的Unit Converter用來轉換各種單位（包含貨幣）也跟著一起壽終正寢 —— 這使得我跟我老婆去採購國外的東西的時候很不方便。

所以稍微研究一下Safari App Extension的限制以後，在這限制下做出一個能符合我們需求的東西，也順便放出來給需要的人來研究一下。也做了一個macOS App，用以紀錄貨品所在網頁，轉換歷史，以及提供最划算的信用卡刷卡資訊（需要自行輸入信用卡資料 -- 放心，只有回饋率等等簡單的資料而已）

是用很零碎的時間寫的，並沒有寫得很好，也請見諒，也沒特別去做圖標... 我是個美術白痴，有人能提供圖標的話會很感謝。

## 鳴謝

- 主要貨幣API來源是[*fixer.io*](https://fixer.io)，這個提供了每個月1000次的API Call。老實講這個數量可能不太夠，之後會用一個中介server來避免API Call exceed。但是，無論如何這個貨幣來源的資料是來自於這個網站，這個credit是屬於這個網站的，這網站API更新得相當迅速且up rate非常優良，再度鳴謝！
- 特別感謝 [flaticon](www.flaticon.com) 的 [Kiranshastry](https://www.flaticon.com/authors/kiranshastry) 提供了tool bar Icon! 說真的這個pdf格式的icon我還真拿他一籌莫展，再次感謝!

## 安裝

Safari App Extension跟以前的Safari Extension不同，他**無法**單獨安裝Safari Extension，他必須依附於一個macOS Application，所以必須要像普通App一樣拖拉進Application資料夾且點擊。

1. 從[Release頁面](https://github.com/Rayer/CurrencyConverter/releases)下載`CurrencyConverter.app.zip`，目前版本是1.5。預設我放上去的版本都是開發者簽名過且AppConnect認證過的application。
2. 就像普通macOS App一樣，把他丟進Application
3. 執行App，按下Enable/Disable extension。如果沒有反應的話，請打開Safari -> Preference -> Extensions，啟動CurrencyConverter。
4. 他會自動打開Safari Preference，把Plugin的CurrencyConverter打勾即可。


## 主要功能

1. 可以在Safari的工具列按鈕上設定需要的貨幣單位。
1. 在網頁上的貨幣數字點兩下，或者直接選取，右鍵會出現轉換結果。
1. 自動取得匯率資料，並且提供即時匯率比例轉換。
1. 提供自動計算信用卡刷卡外幣手續費。
1. 按下右鍵轉換結果，可以拷貝結果進剪貼簿，拷貝的格式可以在工具列按鈕上設定。
1. 轉換結果會同步進Application，方便查詢比價以及信用卡價格查詢，提供信用卡現金回饋，點數資訊以及折抵以後最低價格
1. 可以設定信用卡Profile，用以計算最划算的信用卡


## 限制

1. ~~首先，我不確定這東西很多人用的話，會不會讓一個月1000的quota擠爆。真的有這問題的話，我會用自己的server來解決。~~ 現在我架設自己的server來解決這問題，希望他不要被打爆（不可能吧！？）
2. 沒有i18n....說真的也不太需要吧
