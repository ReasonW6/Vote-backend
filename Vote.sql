/*==============================================================*/
/* DBMS name:      Microsoft SQL Server 2012                    */
/* Created on:     2025/06/09 16:30:00                          */
/* Description:    根据最终设计报告优化和完善的数据库脚本 (已修正) */
/*==============================================================*/

-- =============================================================
-- 第一步：清理环境，删除已有的对象，确保脚本可重复执行
-- =============================================================
-- 删除外键约束
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[dbo].[FK_VOTES_TO_USERS]'))
ALTER TABLE [dbo].[Votes] DROP CONSTRAINT [FK_VOTES_TO_USERS]
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[dbo].[FK_OPTIONS_TO_VOTES]'))
ALTER TABLE [dbo].[Options] DROP CONSTRAINT [FK_OPTIONS_TO_VOTES]
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[dbo].[FK_VOTERECORDS_TO_USERS]'))
ALTER TABLE [dbo].[Vote_Records] DROP CONSTRAINT [FK_VOTERECORDS_TO_USERS]
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[dbo].[FK_VOTERECORDS_TO_OPTIONS]'))
ALTER TABLE [dbo].[Vote_Records] DROP CONSTRAINT [FK_VOTERECORDS_TO_OPTIONS]
GO

-- 删除已有的高级对象
IF EXISTS (SELECT 1 FROM sys.views WHERE object_id = OBJECT_ID(N'[dbo].[V_VoteResults]'))
DROP VIEW [dbo].[V_VoteResults]
GO
IF EXISTS (SELECT 1 FROM sys.procedures WHERE object_id = OBJECT_ID(N'[dbo].[sp_CastVote]'))
DROP PROCEDURE [dbo].[sp_CastVote]
GO
IF EXISTS (SELECT 1 FROM sys.triggers WHERE object_id = OBJECT_ID(N'[dbo].[trg_UpdateVoteCount]'))
DROP TRIGGER [dbo].[trg_UpdateVoteCount]
GO

-- 删除已有的表
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Vote_Records]')) DROP TABLE [dbo].[Vote_Records]
GO
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Options]')) DROP TABLE [dbo].[Options]
GO
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Votes]')) DROP TABLE [dbo].[Votes]
GO
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Users]')) DROP TABLE [dbo].[Users]
GO


-- =============================================================
-- 第二步：创建数据表及所有完整性约束
-- =============================================================

--- 创建 Users (用户表)
CREATE TABLE Users (
   UserID               INT                  IDENTITY(1,1) NOT NULL,
   Username             VARCHAR(20)          NOT NULL,
   Password             VARCHAR(50)          NOT NULL,
   Email                VARCHAR(50)          NOT NULL,
   UserRole             VARCHAR(10)          NOT NULL,
   CreatedAtUser        DATETIME             NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT GETDATE(),
   CONSTRAINT PK_USERS PRIMARY KEY (UserID),
   CONSTRAINT UQ_Users_Username UNIQUE (Username),
   CONSTRAINT UQ_Users_Email UNIQUE (Email),
   CONSTRAINT CK_UserRole CHECK (UserRole IN ('admin', 'user'))
);
GO

--- 创建 Votes (投票表)
CREATE TABLE Votes (
   VoteID               INT                  IDENTITY(1,1) NOT NULL,
   UserID               INT                  NOT NULL,
   Title                VARCHAR(100)         NOT NULL,
   Description          TEXT                 NULL,
   StartTime            DATETIME             NOT NULL,
   EndTime              DATETIME             NOT NULL,
   VoteType             VARCHAR(10)          NOT NULL,
   IsAnonymous          BIT                  NOT NULL CONSTRAINT DF_Votes_IsAnonymous DEFAULT 0,
   CreatedAtVote        DATETIME             NOT NULL CONSTRAINT DF_Votes_CreatedAt DEFAULT GETDATE(),
   CONSTRAINT PK_VOTES PRIMARY KEY (VoteID),
   CONSTRAINT CK_VoteType CHECK (VoteType IN ('single', 'multiple'))
);
GO

--- 创建 Options (选项表)
CREATE TABLE Options (
   OptionID             INT                  IDENTITY(1,1) NOT NULL,
   VoteID               INT                  NOT NULL,
   OptionText           VARCHAR(100)         NOT NULL,
   VoteCount            INT                  NOT NULL CONSTRAINT DF_Options_VoteCount DEFAULT 0,
   CONSTRAINT PK_OPTIONS PRIMARY KEY (OptionID)
);
GO

--- 创建 Vote_Records (投票记录表)
CREATE TABLE Vote_Records (
   RecordID             INT                  IDENTITY(1,1) NOT NULL,
   UserID               INT                  NOT NULL,
   OptionID             INT                  NOT NULL,
   VoteTime             DATETIME             NOT NULL CONSTRAINT DF_VoteRecords_VoteTime DEFAULT GETDATE(),
   CONSTRAINT PK_VOTE_RECORDS PRIMARY KEY (RecordID)
);
GO

-- =============================================================
-- 第三步：添加外键约束
-- =============================================================
ALTER TABLE Votes ADD CONSTRAINT FK_VOTES_TO_USERS FOREIGN KEY (UserID) REFERENCES Users (UserID) ON DELETE CASCADE;
GO
ALTER TABLE Options ADD CONSTRAINT FK_OPTIONS_TO_VOTES FOREIGN KEY (VoteID) REFERENCES Votes (VoteID) ON DELETE CASCADE;
GO
ALTER TABLE Vote_Records ADD CONSTRAINT FK_VOTERECORDS_TO_USERS FOREIGN KEY (UserID) REFERENCES Users (UserID); -- ON DELETE NO ACTION (默认)
GO
ALTER TABLE Vote_Records ADD CONSTRAINT FK_VOTERECORDS_TO_OPTIONS FOREIGN KEY (OptionID) REFERENCES Options (OptionID) ON DELETE CASCADE;
GO

-- =============================================================
-- 第四步：创建视图、索引、存储过程和触发器
-- =============================================================

--- 1. 创建视图 ---
PRINT '创建视图 V_VoteResults...'
GO
CREATE VIEW V_VoteResults AS
SELECT
    v.VoteID,
    v.Title AS VoteTitle,
    v.Description,
    v.EndTime,
    o.OptionID,
    o.OptionText,
    o.VoteCount
FROM
    Votes AS v
JOIN
    Options AS o ON v.VoteID = o.VoteID;
GO

--- 2. 创建索引 ---
PRINT '创建非聚集索引以优化查询...'
GO
CREATE NONCLUSTERED INDEX IX_Votes_UserID ON Votes(UserID);
GO
CREATE NONCLUSTERED INDEX IX_Options_VoteID ON Options(VoteID);
GO
CREATE NONCLUSTERED INDEX IX_VoteRecords_UserID ON Vote_Records(UserID);
GO
CREATE NONCLUSTERED INDEX IX_VoteRecords_OptionID ON Vote_Records(OptionID);
GO

--- 3. 创建存储过程 ---
PRINT '创建存储过程 sp_CastVote...'
GO
CREATE PROCEDURE sp_CastVote
    @InputUserID INT,
    @InputOptionID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @VoteID INT;
    DECLARE @VoteType VARCHAR(10);

    -- 获取投票ID和类型
    SELECT @VoteID = v.VoteID, @VoteType = v.VoteType
    FROM Options o
    JOIN Votes v ON o.VoteID = v.VoteID
    WHERE o.OptionID = @InputOptionID;

    -- 检查是否为单选投票，且用户是否已投过票
    IF @VoteType = 'single' AND EXISTS (
        SELECT 1
        FROM Vote_Records vr
        JOIN Options o ON vr.OptionID = o.OptionID
        WHERE vr.UserID = @InputUserID AND o.VoteID = @VoteID
    )
    BEGIN
        RAISERROR ('您已经参与过本次单选投票，请勿重复提交。', 16, 1);
        RETURN;
    END

    -- 检查是否为多选投票，且用户是否已对同一选项投过票
    IF @VoteType = 'multiple' AND EXISTS (
        SELECT 1
        FROM Vote_Records vr
        WHERE vr.UserID = @InputUserID AND vr.OptionID = @InputOptionID
    )
    BEGIN
        RAISERROR ('您已经投过这个选项了，请勿重复提交。', 16, 1);
        RETURN;
    END

    -- 使用事务保证操作的原子性
    BEGIN TRANSACTION;
    BEGIN TRY
        INSERT INTO Vote_Records (UserID, OptionID) VALUES (@InputUserID, @InputOptionID);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW; -- 重新抛出错误
    END CATCH
END
GO

--- 4. 创建触发器 ---
PRINT '创建触发器 trg_UpdateVoteCount...'
GO
CREATE TRIGGER trg_UpdateVoteCount
ON Vote_Records
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE Options
    SET VoteCount = VoteCount + 1
    WHERE OptionID IN (SELECT OptionID FROM inserted);
END
GO

PRINT '数据库对象创建完成！'
GO

-- =======================================
-- 插入示例数据
-- =======================================
-- 插入用户数据
INSERT INTO Users (Username, Password, Email, UserRole) VALUES 
('admin', '123456', 'admin@example.com', 'admin'),
('user', '123456', 'user@example.com', 'user');
GO

-- 插入投票数据 (注意：这里的 UserID 1 对应 admin, UserID 2 对应 user)
INSERT INTO Votes (UserID, Title, Description, StartTime, EndTime, VoteType, IsAnonymous) VALUES
(1, '喜欢的编程语言', '请从以下选项中选出你最喜欢的编程语言。', '2025-06-01', '2025-07-30', 'multiple', 0),
(2, '大作业是否提交', '请确认您是否已按时提交数据库大作业。', '2025-05-20', '2025-06-05', 'single', 1);
GO

-- 插入选项数据 (注意：这里的 VoteID 1, 2 对应上面的投票)
INSERT INTO Options (VoteID, OptionText) VALUES
(1, 'Java'),
(1, 'Python'),
(1, 'C/C++'),
(1, '其他'),
(2, '是，已提交'),
(2, '否，未提交');
GO

--------------------------------------------
-- 插入示例数据
--------------------------------------------
PRINT '正在创建24个新的测试用户...';
GO
DECLARE @i INT = 1;
WHILE @i <= 24
BEGIN
    DECLARE @username VARCHAR(20) = 'testuser' + CAST(@i AS VARCHAR(2));
    DECLARE @email VARCHAR(50) = 'testuser' + CAST(@i AS VARCHAR(2)) + '@example.com';
    IF NOT EXISTS (SELECT 1 FROM Users WHERE Username = @username)
    BEGIN
        INSERT INTO Users (Username, Password, Email, UserRole)
        VALUES (@username, '123456', @email, 'user');
    END
    SET @i = @i + 1;
END
GO

-- 第二步: 声明变量并获取选项ID
PRINT '正在获取 "大作业是否提交" 投票的选项ID...';
GO
DECLARE @YesOptionID INT, @NoOptionID INT, @VoteID INT;

-- 根据投票标题找到对应的 VoteID
SELECT @VoteID = VoteID FROM Votes WHERE Title = '大作业是否提交';

-- 根据 VoteID 和选项文本找到对应的 OptionID
SELECT @YesOptionID = OptionID FROM Options WHERE VoteID = @VoteID AND OptionText = '是，已提交';
SELECT @NoOptionID = OptionID FROM Options WHERE VoteID = @VoteID AND OptionText = '否，未提交';

-- 检查选项ID是否找到
IF @YesOptionID IS NULL OR @NoOptionID IS NULL
BEGIN
    PRINT '错误：未能在 "大作业是否提交" 投票中找到 "是，已提交" 或 "否，未提交" 选项。请检查数据是否正确。';
END
ELSE
BEGIN
    PRINT '选项ID获取成功, YesOptionID = ' + CAST(@YesOptionID AS VARCHAR) + ', NoOptionID = ' + CAST(@NoOptionID AS VARCHAR);

    -- 第三步: 模拟用户投票
    PRINT '正在模拟用户投票...';
    
    -- 为 "是，已提交" 投20票
    PRINT '为 "是，已提交" 投20票...';
    DECLARE @j INT = 1;
    DECLARE @userID INT;
    WHILE @j <= 20
    BEGIN
        -- 获取对应的 testuser 的 UserID
        SELECT @userID = UserID FROM Users WHERE Username = 'testuser' + CAST(@j AS VARCHAR(2));
        
        -- 调用存储过程投票
        EXEC sp_CastVote @InputUserID = @userID, @InputOptionID = @YesOptionID;
        SET @j = @j + 1;
    END

    -- 为 "否，未提交" 投4票
    PRINT '为 "否，未提交" 投4票...';
    SET @j = 21; -- 从第21个测试用户开始
    WHILE @j <= 24
    BEGIN
        -- 获取对应的 testuser 的 UserID
        SELECT @userID = UserID FROM Users WHERE Username = 'testuser' + CAST(@j AS VARCHAR(2));

        -- 调用存储过程投票
        EXEC sp_CastVote @InputUserID = @userID, @InputOptionID = @NoOptionID;
        SET @j = @j + 1;
    END

    PRINT '投票操作完成！';
END
GO