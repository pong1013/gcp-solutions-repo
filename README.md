# GCP CRM Migration Solutions

這個 repo 用來整理 Company X CRM migration case study 的 GCP 方案。

目前會保留三種方向，方便比較不同取捨：

- 最簡單方案
- 最便宜方案
- 最完整方案

三個方向先放在同一個 repo，因為它們會共用一些資料定義、命名習慣、SQL 想法和文件。等最後選定方向後，再把被採用的方案整理成正式 production implementation。

## Visual guides

- [Simplest Architecture Visual Guide](https://pong1013.github.io/gcp-solutions-repo/simplest/simplest-architecture-visual.html
)：互動式 HTML，說明 simplest 架構、8 個實作步驟、每一步的目的與需求對應，以及整體優化後的結果。

如果是在 GitHub repo 頁面直接點 `.html` 檔，GitHub 通常會顯示原始碼，不會像網頁一樣執行。要用網頁方式開啟，可以下載後本機開啟，或啟用 GitHub Pages 後從 Pages URL 進入。

## Layout

- `simplest/`
- `cheapest/`
- `complete/`
- `shared/`

## Notes

這個 repo 只放方案、設定、程式碼和文件。不要放真實 CRM CSV、Oracle export、credentials、service account key 或 Salesforce token。
