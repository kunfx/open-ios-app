# 资源库 iOS App（SwiftUI + Laravel API）

这是一个**独立**的 iPhone 客户端，数据全部通过 Laravel API 获取，App 不会、也不能直连 MySQL。
本目录之外的任何 PHP 文件都不需要改动（除了在 `bootstrap/app.php` 里注册一次 API 路由）。

```
ios-app/
├─ backend/                  # 复制到 Laravel 项目根目录即可使用
│  ├─ app/Http/Controllers/Api/*
│  ├─ app/Http/Middleware/ApiTokenAuth.php
│  ├─ app/Models/ApiToken.php
│  ├─ database/migrations/2026_10_23_000000_create_api_tokens_table.php
│  └─ routes/api.php
├─ ios/                      # XcodeGen 工程定义 + SwiftUI 源码
│  ├─ project.yml
│  └─ ResourceApp/
└─ .github/workflows/ios-unsigned-ipa.yml
```

---

## 一、后端安装（5 分钟）

### 1. 复制文件

把 `ios-app/backend/` 里的内容按相同路径覆盖到 Laravel 项目根目录：

| 本目录 | 目标位置 |
| --- | --- |
| `backend/app/Http/Controllers/Api/` | `app/Http/Controllers/Api/` |
| `backend/app/Http/Middleware/ApiTokenAuth.php` | `app/Http/Middleware/ApiTokenAuth.php` |
| `backend/app/Models/ApiToken.php` | `app/Models/ApiToken.php` |
| `backend/database/migrations/2026_10_23_000000_create_api_tokens_table.php` | `database/migrations/` |
| `backend/routes/api.php` | `routes/api.php` |

> 不会覆盖你现有的任何控制器、模型或路由文件。

### 2. 注册 API 路由和中间件别名

打开 `bootstrap/app.php`，改成下面这样（只加 3 处）：

```php
return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',   // ① 新增
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // ② 新增：api.token 中间件别名
        $middleware->alias([
            'api.token' => \App\Http\Middleware\ApiTokenAuth::class,
        ]);

        $middleware->validateCsrfTokens(except: [
            'pay/epay/notify',
            'pay/bepusdt/notify',
        ]);
        $middleware->web(append: [
            \App\Http\Middleware\RecordVisitor::class,
        ]);
    })
```

> API 路由自带 `/api` 前缀，`routes/api.php` 里不要再写 `prefix('api')`。
> API 路由不在 `web` 中间件组里，因此没有 Session / CSRF，纯 Bearer Token。

### 3. 建表 + 清缓存

```bash
php artisan migrate
php artisan optimize:clear
```

### 4. 可选环境变量（`.env`）

```env
# 登录 token 有效期（天）
API_TOKEN_TTL_DAYS=90

# 同一 IP 是否只能注册一个账号（默认 true）
API_REGISTER_UNIQUE_IP=true

# pan.ifeng.app 网盘 secure_link 密钥（不填则使用站内现有默认值）
PAN_SECURE_LINK_SECRET=IFeng_Pan_2026_N7qL4xV9mK2pR8cT5sH1
```

> 如果执行过 `php artisan config:cache`，修改 `.env` 后需要再执行一次 `php artisan config:clear`，
> 否则 `env()` 读不到新值（此时会使用上面的默认值，功能仍可正常使用）。

### 5. 验证

浏览器访问 `https://你的域名/api/health`，应返回：

```json
{"success":true,"data":{"status":"ok","name":"ios-resource-app-api","time":"..."}}
```

再测试登录：

```bash
curl -X POST https://你的域名/api/login \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"你的邮箱\",\"password\":\"你的密码\",\"device_name\":\"iPhone\"}"
```

成功会返回 `data.token` 和 `data.user`。之后所有需要登录的接口都带：

```
Authorization: Bearer <token>
```

---

## 二、API 一览

统一响应格式：

```json
{ "success": true, "data": {}, "message": null }
```

失败：

```json
{ "success": false, "message": "错误提示", "errors": { "email": ["..."] } }
```

分页数据在 `data` 内：

```json
{ "items": [], "page": 1, "per_page": 20, "total": 0, "last_page": 1, "has_more": false }
```

| 方法 | 路径 | 登录 | 说明 |
| --- | --- | --- | --- |
| GET | `/api/health` | 否 | 健康检查（App 的“测试连接”） |
| POST | `/api/login` | 否 | 登录，返回一次性 token |
| POST | `/api/register` | 否 | 注册（QQ/163/Gmail/新浪邮箱） |
| POST | `/api/logout` | 是 | 注销当前 token |
| GET | `/api/home` | 可选 | 首页聚合：推荐/应用/游戏/巨魔/文章/分类 |
| GET | `/api/apps` | 可选 | 资源列表，支持 `q`、`main`、`category_id`、`sort`、`page`、`per_page` |
| GET | `/api/apps/{id}` | 可选 | 资源详情（登录后额外返回 `unlocked`） |
| GET | `/api/categories` | 可选 | 两级分类树 + 资源数量 |
| GET | `/api/articles` | 可选 | 教程文章列表 |
| GET | `/api/articles/{id}` | 可选 | 文章详情 + 上一篇/下一篇 |
| GET | `/api/user/profile` | 是 | 积分、VIP、今日免费额度、签到、未读数 |
| POST | `/api/user/profile` | 是 | 修改昵称/头像/密码 |
| POST | `/api/user/sign-in` | 是 | 每日签到 |
| GET | `/api/user/downloads` | 是 | 下载记录（分页） |
| GET | `/api/user/points` | 是 | 积分明细（分页） |
| GET | `/api/user/invitations` | 是 | 邀请链接与邀请统计（赚取积分页） |
| GET | `/api/messages` | 是 | 站内消息（分页） |
| POST | `/api/messages/{id}/read` | 是 | 单条已读 |
| POST | `/api/messages/read-all` | 是 | 全部已读 |
| POST | `/api/apps/{id}/download` | 是 | 下载第一步 |
| POST | `/api/apps/{id}/download/confirm` | 是 | 下载第二步（付费资源扣积分） |
| GET | `/api/download/{app}/{index}` | 签名 | 2 小时有效的跳转入口（App 的下载按钮） |

### 下载流程（权限全部由服务端判定）

```
POST /api/apps/12/download
  ├─ REQUIRE_CONFIRM  → 弹确认框 → POST /api/apps/12/download/confirm
  ├─ DOWNLOAD_READY   → 直接返回签名链接
  ├─ REPEAT_DOWNLOAD  → 重复下载，不再扣分/扣次数
  ├─ FREE_LIMIT_NOTIFY→ 免费额度已扣 1 次
  └─ FREE_LIMIT_EXCEEDED(429) → 提示今日免费次数用完
```

`download_links[].path` 形如：

```
/api/download/12/0?expires=1769...&signature=...
```

App 用自己配置的服务器域名补全后，交给 App 内置的下载管理器（`URLSession` 下载任务）保存到 App 沙盒。该地址：

1. 校验 Laravel 签名 + 是否过期；
2. 从数据库读取真实下载地址；
3. 若为 `pan.ifeng.app` 的 IPA，再附加 Nginx `secure_link` 参数；
4. `302` 跳转。

真实地址永远不会出现在 API JSON 里。

### 安全设计

- **Token**：明文只在登录响应中出现一次；数据库仅存 `sha256(token)`（`api_tokens.token_hash`）。
- **身份**：每个请求都重新校验 token 是否过期、用户是否仍存在；校验后注入 `web` guard，因此直接复用了你现有的 `DownloadController`，积分扣除 / 免费次数 / VIP 判断与网页端完全一致。
- **下载**：签名链接 2 小时有效，`DownloadLinkController` 不信任 App 传来的任何参数，只按 `app_id + index` 从数据库取真实地址。
- **注册**：邮箱域名白名单 + 同 IP 限注册（可在 `.env` 关闭）。
- **限流**：登录 10 次/分钟、注册 5 次/分钟、业务接口 60 次/分钟。

---

## 三、iOS 端

### 本地构建（需要 macOS + Xcode 15+）

```bash
cd ios-app/ios
brew install xcodegen
xcodegen generate
open ResourceApp.xcodeproj
```

选择模拟器直接运行；真机需要你自己的签名证书（Account 里登录 Apple ID 后选 Team 即可）。

- Bundle ID：`com.appku.top`（可改 `project.yml`）
- 最低系统：iOS 16.0
- 默认服务器：`https://ifeng.app`
- 运行中可在 **我的 → 服务器设置** 或登录页底部修改，修改后会退出登录

### 云端构建未签名 IPA（GitHub Actions）

1. 把整个 `ios-app/` 放到仓库根目录（与 `app/`、`routes/` 同级），至少要有 `project.yml` 和 `ResourceApp/` 源码目录。
2. 把 `ios-app/.github/workflows/ios-unsigned-ipa.yml` 复制到仓库根目录的 `.github/workflows/`。
3. push 到 `main`/`master`，或在 Actions 页面手动 **Run workflow**。
4. 构建完成后在 Artifacts 下载 `ResourceApp-unsigned-ipa-<构建号>`。

> 工作流会自动查找 `project.yml`，所以 `ios-app/ios/project.yml`、`ios/project.yml`、根目录 `project.yml` 三种结构都能构建。
> 如果报 `working directory ... No such file or directory`，说明仓库里没有上传 iOS 源码，或 `project.yml` 不在上述位置；重新上传 `ios-app/ios` 整个目录后再运行即可。

工作流做的事：`xcodegen generate` → `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO` → 打包 `Payload/ResourceApp.app` → `zip` 成 `.ipa`。

> 未签名 IPA 不能直接安装。用 **Sideloadly / AltStore / TrollStore / 企业签名** 重新签名后再装到 iPhone。

### 目录说明

```
ios/ResourceApp/
├─ ResourceApp.swift          # @main
├─ App/RootView.swift         # 5 个 Tab：应用 / 游戏 / 巨魔 / 下载 / 我的
├─ Core/
│  ├─ APIClient.swift         # 网络层、Bearer Token、错误映射
│  ├─ AppConfig.swift         # 服务器地址（可运行时修改）
│  ├─ AppRouter.swift         # 全局标签页切换（下载完成后跳「下载」）
│  ├─ DownloadManager.swift   # App 内置下载管理：进度/暂停/继续/重试/本地文件
│  ├─ SessionStore.swift      # 登录态、Keychain 恢复、资料刷新
│  ├─ KeychainStore.swift     # token 只存 Keychain
│  ├─ Theme.swift             # 配色与卡片样式
│  └─ Extensions.swift        # HTML 转纯文本、日期格式化
├─ Models/                    # User / ResourceModels / ContentModels
├─ Components/                # 通用图片、卡片、空状态、搜索框、HTML 渲染
└─ Features/
   ├─ Auth/                   # 登录 / 注册 / 服务器地址（「我的」未登录时直接显示）
   ├─ Categories/             # 应用/游戏/巨魔三个标签页 + 顶部搜索 + 子分类
   ├─ Downloads/              # 内置下载管理列表（进度条、分享/导出）
   ├─ Apps/                   # 详情 + 下载弹窗（加入 App 内下载）
   ├─ Articles/               # 教程文章
   └─ Profile/                # 个人中心、修改资料、签到/邀请、下载记录、积分、消息、设置
```

### 标签页说明

| 标签 | 内容 |
| --- | --- |
| 应用 / 游戏 / 巨魔 | 对应网站的三个主分类，顶部固定搜索框（左侧放大镜），支持子分类与排序 |
| 下载 | App 内置下载管理器，列表显示每个任务的进度条、暂停/继续/重试/删除、完成后分享或存储到文件 |
| 我的 | 未登录时直接显示登录框；登录后显示与 PHP 网站个人中心一致的子菜单（修改资料、下载记录、签名证书、升级会员、我的积分、赚取积分、我的订单、问题反馈） |

> 签名证书、升级会员、我的订单、问题反馈属于网站端的支付/工单流程，App 内保留同名入口并跳转网页版完成；其余功能为原生页面。
> 站内消息、教程文章、服务器设置放在「我的」页面下方的独立卡片中，避免打乱与网站一致的子菜单。
> 下载不会再打开浏览器，文件保存在 App 沙盒中。

---

## 四、常见问题

| 现象 | 排查 |
| --- | --- |
| `/api/health` 404 | `bootstrap/app.php` 里没加 `api: __DIR__.'/../routes/api.php'`，或没执行 `php artisan optimize:clear` |
| 所有接口 500，日志提示 `api.token` 不存在 | 没在 `withMiddleware` 里注册中间件别名 |
| 登录返回 419 | 说明请求走到了 `web` 路由；确认用的是 `/api/login` 且请求头 `Accept: application/json` |
| 登录提示“尝试次数过多” | 同一邮箱+IP 5 次失败锁定 60 秒 |
| 下载链接 403 | 链接过期（2 小时）或换了域名/HTTPS，回详情页重新获取 |
| App 提示“网络连接失败” | 检查服务器地址是否需要 `https`、证书是否有效；App 已开启 ATS 任意加载但仍建议用 HTTPS |
| 消息列表为空 | 接口会自动在 `notifications` / `user_notifications` 中选择“当前用户有数据”的那张表；两表都为空时属正常 |
| 签到 500 | 确认 `user_sign_ins` 表存在（网站签到功能已在用） |
| Actions 报 `future Xcode project file format (77)` | CI 的 Xcode 15 打不开 Xcode 16 工程格式；`project.yml` 已固定 `projectFormat: xcode15_3`，若改回默认需把 runner 换成 `macos-15` |

---

## 五、没有改动的东西

- 没有修改任何现有 PHP 控制器/模型/视图/路由。
- 没有新增数据库字段到现有表；只新增了 `api_tokens` 一张表。
- 网页端的登录、积分、VIP、下载逻辑完全照旧；API 只是复用同一套服务端判定。
