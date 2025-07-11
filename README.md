# 网上投票系统
  
它提供了一个清晰、易用的界面，允许用户参与投票活动，并为管理员提供了创建和管理投票的权限。  

## 主要功能

* **用户认证**: 支持用户登录和注册功能。 
* **角色权限**: 系统分为“普通用户”和“管理员”两种角色，拥有不同的操作权限。 
    * **管理员**: 可以创建新的投票、设置投票规则（如单/多选、是否匿名）以及删除投票。 
    * **普通用户**: 可以浏览所有投票活动、参与投票并查看投票结果。 
* **投票生命周期**: 投票活动具有明确的“未开始”、“进行中”和“已结束”状态，由其开始和结束时间自动控制。 
* **投票多样性**: 支持单选和多选两种投票类型，并可设置投票是否匿名发布。 
* **实时结果展示**: 投票结果以直观的百分比条形图展示。 

## 技术栈

* **前端 (Frontend)**: HTML, Tailwind CSS, 原生 JavaScript (Vanilla JS)
* **后端 (Backend)**: Node.js, Express.js
* **数据库 (Database)**: Microsoft SQL Server

## 环境要求

* Node.js (建议 v14 或更高版本)
* npm (通常随 Node.js 一起安装)
* Microsoft SQL Server (任何版本，例如免费的 Express Edition)
* SQL Server 管理工具 (例如 SSMS 或 VS Code 的 mssql 插件)

## 安装与启动

请按照以下步骤来设置和运行本项目：

**1. 获取项目文件**

将所有项目文件下载或克隆到您的本地计算机，并创建一个文件夹来保存它们（例如`Vote`）。

**2. 数据库配置**

* 打开您的 SQL Server 管理工具 (如 SSMS)。
* 连接到您的数据库实例。
* 执行项目中的 `Vote.sql` 脚本。  这将自动创建所需的数据库、所有表、视图、存储过程，并插入初始数据。

**3. 后端配置**

* 在终端中，进入 `Vote` 文件夹：
    ```bash
    cd …/Vote
    ```
* 安装项目所需的所有依赖库：
    ```bash
    npm install
    ```
* 打开 `server.js` 文件，找到 `dbConfig` 对象，并根据您的 SQL Server 连接信息修改 `user`, `password`, `server`, 和 `database` 字段。

**4. 启动应用**

* 确保您的 SQL Server 服务正在运行。
* 在 `Vote` 文件夹的终端中，启动后端服务器：
    ```bash
    node server.js
    ```
* 您应该会看到服务器启动和数据库连接成功的提示。
* 打开您的浏览器，访问以下地址即可开始使用：
    [http://localhost:3000](http://localhost:3000)

## 文件结构

```
程序源代码/
├── public/
│   └── index.html      # 前端界面文件
├── node_modules/       # 项目依赖库
├── package.json        # 项目定义和依赖列表
├── server.js           # 后端服务器与API逻辑
├── README.md           # 本说明文件
└── Vote.sql            # sql脚本文件
```