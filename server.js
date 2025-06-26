// 导入所需的库
const path = require('path');
const express = require('express');
const sql = require('mssql');
const cors = require('cors');

// 创建 Express 应用
const app = express();
const port = 3000; // 我们的服务器将在此端口上运行

// 使用中间件
app.use(cors()); // 允许所有来源的跨域请求
app.use(express.json()); // 能够解析请求体中的 JSON 数据
app.use(express.static(path.join(__dirname, 'public')));

// --- 数据库连接配置 ---
// 这是根据您之前提供的截图信息配置的
const dbConfig = {
    user: 'sa',
    password: '123456',
    server: 'WANG-XUAN\\WANG', // 注意: 在JS中一个反斜杠是转义符, 所以需要两个
    database: '网上投票系统',
    options: {
        encrypt: false,
        trustServerCertificate: true
    }
};

// --- API 端点 (Endpoints) ---

// (之前的注册、登录、获取投票等接口保持不变...)
// ...

// 1. [POST] /api/register - 用户注册
app.post('/api/register', async (req, res) => {
    const { username, password, email, role } = req.body;
    try {
        const pool = await sql.connect(dbConfig);
        const checkUser = await pool.request()
            .input('Username', sql.VarChar, username)
            .input('Email', sql.VarChar, email)
            .query('SELECT * FROM Users WHERE Username = @Username OR Email = @Email');
        if (checkUser.recordset.length > 0) {
            return res.status(409).json({ message: '用户名或邮箱已被注册。' });
        }
        await pool.request()
            .input('Username', sql.VarChar, username)
            .input('Password', sql.VarChar, password)
            .input('Email', sql.VarChar, email)
            .input('UserRole', sql.VarChar, role)
            .query('INSERT INTO Users (Username, Password, Email, UserRole) VALUES (@Username, @Password, @Email, @UserRole)');
        res.status(201).json({ message: '注册成功！' });
    } catch (err) {
        res.status(500).json({ message: '服务器内部错误', error: err.message });
    }
});


// 2. [POST] /api/login - 用户登录
app.post('/api/login', async (req, res) => {
    const { username, password } = req.body;
    try {
        const pool = await sql.connect(dbConfig);
        const result = await pool.request()
            .input('Username', sql.VarChar, username)
            .input('Password', sql.VarChar, password)
            .query('SELECT UserID, Username, UserRole FROM Users WHERE Username = @Username AND Password = @Password');
        if (result.recordset.length > 0) {
            res.status(200).json(result.recordset[0]);
        } else {
            res.status(401).json({ message: '用户名或密码错误' });
        }
    } catch (err) {
        res.status(500).json({ message: '服务器内部错误', error: err.message });
    }
});

// 3. [GET] /api/users/:userId/voted-records - (新增) 获取用户的投票记录
app.get('/api/users/:userId/voted-records', async (req, res) => {
    const { userId } = req.params;
    try {
        const pool = await sql.connect(dbConfig);
        const result = await pool.request()
            .input('UserID', sql.Int, userId)
            .query(`
                SELECT o.VoteID, vr.OptionID 
                FROM Vote_Records vr 
                JOIN Options o ON vr.OptionID = o.OptionID 
                WHERE vr.UserID = @UserID
            `);
        
        // 将结果处理成前端需要的格式: { voteId1: [optionId1, optionId2], ... }
        const userVotes = result.recordset.reduce((acc, record) => {
            if (!acc[record.VoteID]) {
                acc[record.VoteID] = [];
            }
            acc[record.VoteID].push(record.OptionID);
            return acc;
        }, {});

        res.status(200).json(userVotes);
    } catch (err) {
        res.status(500).json({ message: '获取用户投票记录失败', error: err.message });
    }
});

// 4. [GET] /api/votes - 获取所有投票列表
app.get('/api/votes', async (req, res) => {
    try {
        const pool = await sql.connect(dbConfig);
        const result = await pool.request().query(`
            SELECT v.*, u.Username AS PublisherName 
            FROM Votes v JOIN Users u ON v.UserID = u.UserID
            ORDER BY v.StartTime DESC
        `);
        res.status(200).json(result.recordset);
    } catch (err) {
        res.status(500).json({ message: '获取投票列表失败', error: err.message });
    }
});

// 5. [GET] /api/votes/:voteId/options - 获取特定投票的所有选项
app.get('/api/votes/:voteId/options', async (req, res) => {
    const { voteId } = req.params;
    try {
        const pool = await sql.connect(dbConfig);
        const result = await pool.request()
            .input('VoteID', sql.Int, voteId)
            .query('SELECT * FROM Options WHERE VoteID = @VoteID ORDER BY OptionID');
        res.status(200).json(result.recordset);
    } catch (err) {
        res.status(500).json({ message: '获取投票选项失败', error: err.message });
    }
});

// 6. [POST] /api/vote - 提交一个投票
app.post('/api/vote', async (req, res) => {
    const { userId, optionIds } = req.body;
    try {
        const pool = await sql.connect(dbConfig);
        for (const optionId of optionIds) {
            await pool.request()
                .input('InputUserID', sql.Int, userId)
                .input('InputOptionID', sql.Int, optionId)
                .execute('sp_CastVote');
        }
        res.status(200).json({ message: '投票成功！' });
    } catch (err) {
        res.status(400).json({ message: err.originalError ? err.originalError.message : err.message });
    }
});

// 7. [POST] /api/votes - 创建一个新的投票
app.post('/api/votes', async (req, res) => {
    const { UserID, Title, Description, StartTime, EndTime, VoteType, IsAnonymous, Options } = req.body;
    if (!Options || Options.length < 2) {
        return res.status(400).json({ message: "至少需要提供两个选项。" });
    }
    const pool = await sql.connect(dbConfig);
    const transaction = new sql.Transaction(pool);
    try {
        await transaction.begin();
        const voteResult = await new sql.Request(transaction)
            .input('UserID', sql.Int, UserID).input('Title', sql.VarChar, Title).input('Description', sql.Text, Description)
            .input('StartTime', sql.DateTime, new Date(StartTime)).input('EndTime', sql.DateTime, new Date(EndTime))
            .input('VoteType', sql.VarChar, VoteType).input('IsAnonymous', sql.Bit, IsAnonymous)
            .query('INSERT INTO Votes (UserID, Title, Description, StartTime, EndTime, VoteType, IsAnonymous) OUTPUT INSERTED.VoteID VALUES (@UserID, @Title, @Description, @StartTime, @EndTime, @VoteType, @IsAnonymous)');
        const newVoteId = voteResult.recordset[0].VoteID;
        for (const optionText of Options) {
            await new sql.Request(transaction)
                .input('VoteID', sql.Int, newVoteId).input('OptionText', sql.VarChar, optionText)
                .query('INSERT INTO Options (VoteID, OptionText) VALUES (@VoteID, @OptionText)');
        }
        await transaction.commit();
        res.status(201).json({ message: '投票创建成功！', newVoteId: newVoteId });
    } catch (err) {
        await transaction.rollback();
        res.status(500).json({ message: '创建投票失败', error: err.message });
    }
});

// 8. [DELETE] /api/votes/:voteId - 删除一个投票
app.delete('/api/votes/:voteId', async (req, res) => {
    const { voteId } = req.params;
    try {
        const pool = await sql.connect(dbConfig);
        await pool.request().input('VoteID', sql.Int, voteId).query('DELETE FROM Votes WHERE VoteID = @VoteID');
        res.status(200).json({ message: '投票已成功删除' });
    } catch (err) {
        res.status(500).json({ message: '删除投票失败', error: err.message });
    }
});

// 启动服务器
app.listen(port, () => {
    console.log(`✅ 后端服务器已启动，正在 http://localhost:${port} 上监听请求`);
    sql.connect(dbConfig).then(() => {
        console.log('✅ 数据库连接成功');
    }).catch(err => {
        console.error('❌ 数据库连接失败，请检查 server.js 中的 dbConfig 配置:', err);
    });
});
