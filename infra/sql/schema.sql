-- ---------------------------------------------------------------------------
-- Application schema + seed data for the ResFrac API.
-- Idempotent: safe to run repeatedly (used by provision.ps1 and the pipeline).
-- Run against the target database as an Entra admin.
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.Items', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Items
    (
        Id        INT IDENTITY(1,1) PRIMARY KEY,
        Name      NVARCHAR(200)     NOT NULL,
        CreatedAt DATETIME2(0)      NOT NULL CONSTRAINT DF_Items_CreatedAt DEFAULT SYSUTCDATETIME()
    );
END;
GO

-- Seed a few rows only if the table is empty.
IF NOT EXISTS (SELECT 1 FROM dbo.Items)
BEGIN
    INSERT INTO dbo.Items (Name) VALUES
        (N'well-telemetry-baseline'),
        (N'fracture-model-v2'),
        (N'reservoir-sim-config');
END;
GO
