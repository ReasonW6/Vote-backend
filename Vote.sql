/*==============================================================*/
/* DBMS name:      Microsoft SQL Server 2012                    */
/* Created on:     2025/06/09 16:30:00                          */
/* Description:    ����������Ʊ����Ż������Ƶ����ݿ�ű� (������) */
/*==============================================================*/

-- =============================================================
-- ��һ������������ɾ�����еĶ���ȷ���ű����ظ�ִ��
-- =============================================================
-- ɾ�����Լ��
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

-- ɾ�����еĸ߼�����
IF EXISTS (SELECT 1 FROM sys.views WHERE object_id = OBJECT_ID(N'[dbo].[V_VoteResults]'))
DROP VIEW [dbo].[V_VoteResults]
GO
IF EXISTS (SELECT 1 FROM sys.procedures WHERE object_id = OBJECT_ID(N'[dbo].[sp_CastVote]'))
DROP PROCEDURE [dbo].[sp_CastVote]
GO
IF EXISTS (SELECT 1 FROM sys.triggers WHERE object_id = OBJECT_ID(N'[dbo].[trg_UpdateVoteCount]'))
DROP TRIGGER [dbo].[trg_UpdateVoteCount]
GO

-- ɾ�����еı�
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Vote_Records]')) DROP TABLE [dbo].[Vote_Records]
GO
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Options]')) DROP TABLE [dbo].[Options]
GO
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Votes]')) DROP TABLE [dbo].[Votes]
GO
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Users]')) DROP TABLE [dbo].[Users]
GO


-- =============================================================
-- �ڶ������������ݱ�����������Լ��
-- =============================================================

--- ���� Users (�û���)
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

--- ���� Votes (ͶƱ��)
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

--- ���� Options (ѡ���)
CREATE TABLE Options (
   OptionID             INT                  IDENTITY(1,1) NOT NULL,
   VoteID               INT                  NOT NULL,
   OptionText           VARCHAR(100)         NOT NULL,
   VoteCount            INT                  NOT NULL CONSTRAINT DF_Options_VoteCount DEFAULT 0,
   CONSTRAINT PK_OPTIONS PRIMARY KEY (OptionID)
);
GO

--- ���� Vote_Records (ͶƱ��¼��)
CREATE TABLE Vote_Records (
   RecordID             INT                  IDENTITY(1,1) NOT NULL,
   UserID               INT                  NOT NULL,
   OptionID             INT                  NOT NULL,
   VoteTime             DATETIME             NOT NULL CONSTRAINT DF_VoteRecords_VoteTime DEFAULT GETDATE(),
   CONSTRAINT PK_VOTE_RECORDS PRIMARY KEY (RecordID)
);
GO

-- =============================================================
-- ��������������Լ��
-- =============================================================
ALTER TABLE Votes ADD CONSTRAINT FK_VOTES_TO_USERS FOREIGN KEY (UserID) REFERENCES Users (UserID) ON DELETE CASCADE;
GO
ALTER TABLE Options ADD CONSTRAINT FK_OPTIONS_TO_VOTES FOREIGN KEY (VoteID) REFERENCES Votes (VoteID) ON DELETE CASCADE;
GO
ALTER TABLE Vote_Records ADD CONSTRAINT FK_VOTERECORDS_TO_USERS FOREIGN KEY (UserID) REFERENCES Users (UserID); -- ON DELETE NO ACTION (Ĭ��)
GO
ALTER TABLE Vote_Records ADD CONSTRAINT FK_VOTERECORDS_TO_OPTIONS FOREIGN KEY (OptionID) REFERENCES Options (OptionID) ON DELETE CASCADE;
GO

-- =============================================================
-- ���Ĳ���������ͼ���������洢���̺ʹ�����
-- =============================================================

--- 1. ������ͼ ---
PRINT '������ͼ V_VoteResults...'
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

--- 2. �������� ---
PRINT '�����Ǿۼ��������Ż���ѯ...'
GO
CREATE NONCLUSTERED INDEX IX_Votes_UserID ON Votes(UserID);
GO
CREATE NONCLUSTERED INDEX IX_Options_VoteID ON Options(VoteID);
GO
CREATE NONCLUSTERED INDEX IX_VoteRecords_UserID ON Vote_Records(UserID);
GO
CREATE NONCLUSTERED INDEX IX_VoteRecords_OptionID ON Vote_Records(OptionID);
GO

--- 3. �����洢���� ---
PRINT '�����洢���� sp_CastVote...'
GO
CREATE PROCEDURE sp_CastVote
    @InputUserID INT,
    @InputOptionID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @VoteID INT;
    DECLARE @VoteType VARCHAR(10);

    -- ��ȡͶƱID������
    SELECT @VoteID = v.VoteID, @VoteType = v.VoteType
    FROM Options o
    JOIN Votes v ON o.VoteID = v.VoteID
    WHERE o.OptionID = @InputOptionID;

    -- ����Ƿ�Ϊ��ѡͶƱ�����û��Ƿ���Ͷ��Ʊ
    IF @VoteType = 'single' AND EXISTS (
        SELECT 1
        FROM Vote_Records vr
        JOIN Options o ON vr.OptionID = o.OptionID
        WHERE vr.UserID = @InputUserID AND o.VoteID = @VoteID
    )
    BEGIN
        RAISERROR ('���Ѿ���������ε�ѡͶƱ�������ظ��ύ��', 16, 1);
        RETURN;
    END

    -- ����Ƿ�Ϊ��ѡͶƱ�����û��Ƿ��Ѷ�ͬһѡ��Ͷ��Ʊ
    IF @VoteType = 'multiple' AND EXISTS (
        SELECT 1
        FROM Vote_Records vr
        WHERE vr.UserID = @InputUserID AND vr.OptionID = @InputOptionID
    )
    BEGIN
        RAISERROR ('���Ѿ�Ͷ�����ѡ���ˣ������ظ��ύ��', 16, 1);
        RETURN;
    END

    -- ʹ������֤������ԭ����
    BEGIN TRANSACTION;
    BEGIN TRY
        INSERT INTO Vote_Records (UserID, OptionID) VALUES (@InputUserID, @InputOptionID);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW; -- �����׳�����
    END CATCH
END
GO

--- 4. ���������� ---
PRINT '���������� trg_UpdateVoteCount...'
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

PRINT '���ݿ���󴴽���ɣ�'
GO

-- =======================================
-- ����ʾ������
-- =======================================
-- �����û�����
INSERT INTO Users (Username, Password, Email, UserRole) VALUES 
('admin', '123456', 'admin@example.com', 'admin'),
('user', '123456', 'user@example.com', 'user');
GO

-- ����ͶƱ���� (ע�⣺����� UserID 1 ��Ӧ admin, UserID 2 ��Ӧ user)
INSERT INTO Votes (UserID, Title, Description, StartTime, EndTime, VoteType, IsAnonymous) VALUES
(1, 'ϲ���ı������', '�������ѡ����ѡ������ϲ���ı�����ԡ�', '2025-06-01', '2025-07-30', 'multiple', 0),
(2, '����ҵ�Ƿ��ύ', '��ȷ�����Ƿ��Ѱ�ʱ�ύ���ݿ����ҵ��', '2025-05-20', '2025-06-05', 'single', 1);
GO

-- ����ѡ������ (ע�⣺����� VoteID 1, 2 ��Ӧ�����ͶƱ)
INSERT INTO Options (VoteID, OptionText) VALUES
(1, 'Java'),
(1, 'Python'),
(1, 'C/C++'),
(1, '����'),
(2, '�ǣ����ύ'),
(2, '��δ�ύ');
GO

--------------------------------------------
-- ����ʾ������
--------------------------------------------
PRINT '���ڴ���24���µĲ����û�...';
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

-- �ڶ���: ������������ȡѡ��ID
PRINT '���ڻ�ȡ "����ҵ�Ƿ��ύ" ͶƱ��ѡ��ID...';
GO
DECLARE @YesOptionID INT, @NoOptionID INT, @VoteID INT;

-- ����ͶƱ�����ҵ���Ӧ�� VoteID
SELECT @VoteID = VoteID FROM Votes WHERE Title = '����ҵ�Ƿ��ύ';

-- ���� VoteID ��ѡ���ı��ҵ���Ӧ�� OptionID
SELECT @YesOptionID = OptionID FROM Options WHERE VoteID = @VoteID AND OptionText = '�ǣ����ύ';
SELECT @NoOptionID = OptionID FROM Options WHERE VoteID = @VoteID AND OptionText = '��δ�ύ';

-- ���ѡ��ID�Ƿ��ҵ�
IF @YesOptionID IS NULL OR @NoOptionID IS NULL
BEGIN
    PRINT '����δ���� "����ҵ�Ƿ��ύ" ͶƱ���ҵ� "�ǣ����ύ" �� "��δ�ύ" ѡ����������Ƿ���ȷ��';
END
ELSE
BEGIN
    PRINT 'ѡ��ID��ȡ�ɹ�, YesOptionID = ' + CAST(@YesOptionID AS VARCHAR) + ', NoOptionID = ' + CAST(@NoOptionID AS VARCHAR);

    -- ������: ģ���û�ͶƱ
    PRINT '����ģ���û�ͶƱ...';
    
    -- Ϊ "�ǣ����ύ" Ͷ20Ʊ
    PRINT 'Ϊ "�ǣ����ύ" Ͷ20Ʊ...';
    DECLARE @j INT = 1;
    DECLARE @userID INT;
    WHILE @j <= 20
    BEGIN
        -- ��ȡ��Ӧ�� testuser �� UserID
        SELECT @userID = UserID FROM Users WHERE Username = 'testuser' + CAST(@j AS VARCHAR(2));
        
        -- ���ô洢����ͶƱ
        EXEC sp_CastVote @InputUserID = @userID, @InputOptionID = @YesOptionID;
        SET @j = @j + 1;
    END

    -- Ϊ "��δ�ύ" Ͷ4Ʊ
    PRINT 'Ϊ "��δ�ύ" Ͷ4Ʊ...';
    SET @j = 21; -- �ӵ�21�������û���ʼ
    WHILE @j <= 24
    BEGIN
        -- ��ȡ��Ӧ�� testuser �� UserID
        SELECT @userID = UserID FROM Users WHERE Username = 'testuser' + CAST(@j AS VARCHAR(2));

        -- ���ô洢����ͶƱ
        EXEC sp_CastVote @InputUserID = @userID, @InputOptionID = @NoOptionID;
        SET @j = @j + 1;
    END

    PRINT 'ͶƱ������ɣ�';
END
GO