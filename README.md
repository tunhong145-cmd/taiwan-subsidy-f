# Taiwan Subsidy F

F 项目独立静态站点：

- `index.html`：4 步补助申请落地页
- `admin.html`：主管理员全部订单后台，可按投手筛选
- `pages-admin.html`：投手 Page 管理，自动生成 `page1`、`page2`、`page3`……
- `page-admin.html?page=page1`：投手独立订单后台
- `index.html?page=page1`：投手独立落地页
- `supabase-schema.sql`：只管理 F 专用数据表，不修改 A、B 或其他数据表

所有表单项目都必须填写，但不检查姓名、年龄、电话、身份证等内容格式；客户填写内容会按原样进入 F 项目独立数据表。

客户提交成功后会显示姓名与专员 LINE 引导，并在 3 秒后自动跳转。每个 Page 独立配置 LINE、多个 Facebook Pixel、启用状态和后台密码；订单通过 `page_slug` 隔离，原有订单归入 `main`。

首次启用多投手功能前，请在 `taiwan-subsidy` Supabase SQL Editor 中完整执行最新版 `supabase-schema.sql`。

Supabase 项目：`xgjnmhedqwehxgwnlggo`。后台使用现有 `admin@taiwan-subsidy.com` Auth 账号登录。
