
-- PROYECTO:TIENDA DE ABARROTES-DC

USE master;
GO

-- 1. CREACIÓN DE LA BASE DE DATOS
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'TiendaAbarrotesDC')
BEGIN
    ALTER DATABASE TiendaAbarrotesDC SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE TiendaAbarrotesDC;
END
GO

CREATE DATABASE TiendaAbarrotesDC;
GO

USE TiendaAbarrotesDC;
GO

CREATE TABLE Categorias (
    IdCategoria INT PRIMARY KEY IDENTITY(1,1),
    NombreCategoria VARCHAR(100) NOT NULL UNIQUE
);
GO

CREATE TABLE Productos (
    IdProducto INT PRIMARY KEY IDENTITY(1,1),
    NombreProducto VARCHAR(100) NOT NULL,
    IdCategoria INT,
    UnidadMedida VARCHAR(20) DEFAULT 'Unidad', 
    PrecioVenta DECIMAL(10,2) NOT NULL,
    Stock DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    
    CONSTRAINT CHK_Precio CHECK (PrecioVenta > 0),
    FOREIGN KEY (IdCategoria) REFERENCES Categorias(IdCategoria)
);
GO

CREATE TABLE Clientes (
    IdCliente INT PRIMARY KEY IDENTITY(1,1),
    DNI VARCHAR(8) NULL, 
    Alias_Apodo VARCHAR(100) NOT NULL, 
    Telefono VARCHAR(15),
    Direccion VARCHAR(200)
);
GO

CREATE TABLE Proveedores (
    IdProveedor INT PRIMARY KEY IDENTITY(1,1),
    RUC VARCHAR(11) NOT NULL UNIQUE,
    RazonSocial VARCHAR(150) NOT NULL,
    Telefono VARCHAR(15)
);
GO


CREATE TABLE Compras (
    IdCompra INT PRIMARY KEY IDENTITY(1,1),
    IdProveedor INT NOT NULL,
    FechaCompra DATETIME DEFAULT GETDATE(),
    TipoComprobante VARCHAR(20) DEFAULT 'Factura',
    NumComprobante VARCHAR(50),
    TotalCompra DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    CondicionPago VARCHAR(20) DEFAULT 'Contado', 
    
    CONSTRAINT CHK_CondicionPago CHECK (CondicionPago IN ('Contado', 'Credito')),
    FOREIGN KEY (IdProveedor) REFERENCES Proveedores(IdProveedor)
);
GO

CREATE TABLE Detalle_Compras (
    IdDetalleCompra INT PRIMARY KEY IDENTITY(1,1),
    IdCompra INT NOT NULL,
    IdProducto INT NOT NULL,
    Cantidad DECIMAL(10,2) NOT NULL, 
    CostoUnitario DECIMAL(10,2) NOT NULL,
    Subtotal DECIMAL(10,2) NOT NULL,
    
    FOREIGN KEY (IdCompra) REFERENCES Compras(IdCompra),
    FOREIGN KEY (IdProducto) REFERENCES Productos(IdProducto)
);
GO

CREATE TABLE Cuentas_Por_Pagar_Proveedores (
    IdDeudaProveedor INT PRIMARY KEY IDENTITY(1,1),
    IdCompra INT NOT NULL UNIQUE,
    IdProveedor INT NOT NULL,
    SaldoPendiente DECIMAL(10,2) NOT NULL,
    Estado VARCHAR(20) DEFAULT 'Pendiente',
    
    FOREIGN KEY (IdCompra) REFERENCES Compras(IdCompra),
    FOREIGN KEY (IdProveedor) REFERENCES Proveedores(IdProveedor)
);
GO



CREATE TABLE Ventas (
    IdVenta INT PRIMARY KEY IDENTITY(1,1),
    IdCliente INT NULL, 
    FechaVenta DATETIME DEFAULT GETDATE(),
    TotalVenta DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    TipoComprobante VARCHAR(20) DEFAULT 'Ticket Interno', 
    EstadoVenta VARCHAR(20) DEFAULT 'Contado', 
    
    CONSTRAINT CHK_VentaCredito CHECK (EstadoVenta = 'Contado' OR (EstadoVenta = 'Credito' AND IdCliente IS NOT NULL)),
    FOREIGN KEY (IdCliente) REFERENCES Clientes(IdCliente)
);
GO

CREATE TABLE Detalle_Ventas (
    IdDetalle INT PRIMARY KEY IDENTITY(1,1),
    IdVenta INT NOT NULL,
    IdProducto INT NOT NULL,
    Cantidad DECIMAL(10,2) NOT NULL,
    PrecioUnitario_Venta DECIMAL(10,2) NOT NULL, 
    Subtotal DECIMAL(10,2) NOT NULL,
    
    FOREIGN KEY (IdVenta) REFERENCES Ventas(IdVenta),
    FOREIGN KEY (IdProducto) REFERENCES Productos(IdProducto)
);
GO

CREATE TABLE Cuentas_Fiados (
    IdCuenta INT PRIMARY KEY IDENTITY(1,1),
    IdCliente INT NOT NULL,
    IdVenta INT NOT NULL UNIQUE, 
    FechaApertura DATETIME DEFAULT GETDATE(),
    SaldoPendiente DECIMAL(10,2) NOT NULL,
    Estado VARCHAR(20) DEFAULT 'Pendiente', 
    
    FOREIGN KEY (IdCliente) REFERENCES Clientes(IdCliente),
    FOREIGN KEY (IdVenta) REFERENCES Ventas(IdVenta)
);
GO

CREATE TABLE Abonos (
    IdAbono INT PRIMARY KEY IDENTITY(1,1),
    IdCuenta INT NOT NULL,
    FechaAbono DATETIME DEFAULT GETDATE(),
    MontoPagado DECIMAL(10,2) NOT NULL,
    MetodoPago VARCHAR(20) DEFAULT 'Efectivo', 
    
    CONSTRAINT CHK_Monto CHECK (MontoPagado > 0),
    CONSTRAINT CHK_Metodo CHECK (MetodoPago IN ('Efectivo', 'Yape', 'Plin')), 
    FOREIGN KEY (IdCuenta) REFERENCES Cuentas_Fiados(IdCuenta)
);
GO


CREATE TRIGGER trg_IngresoAlmacen
ON Detalle_Compras
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE p
    SET p.Stock = p.Stock + i.Cantidad
    FROM Productos p
    INNER JOIN inserted i ON p.IdProducto = i.IdProducto;
    
    UPDATE c
    SET c.TotalCompra = c.TotalCompra + sub.GranSubtotal
    FROM Compras c
    INNER JOIN (SELECT IdCompra, SUM(Subtotal) AS GranSubtotal FROM inserted GROUP BY IdCompra) sub ON c.IdCompra = sub.IdCompra;
END;
GO


CREATE TRIGGER trg_SalidaAlmacen
ON Detalle_Ventas
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE p
    SET p.Stock = p.Stock - i.Cantidad
    FROM Productos p
    INNER JOIN inserted i ON p.IdProducto = i.IdProducto;
    
    UPDATE v
    SET v.TotalVenta = v.TotalVenta + sub.GranSubtotal
    FROM Ventas v
    INNER JOIN (SELECT IdVenta, SUM(Subtotal) AS GranSubtotal FROM inserted GROUP BY IdVenta) sub ON v.IdVenta = sub.IdVenta;
END;
GO

CREATE TRIGGER trg_GenerarDeudaVecino
ON Ventas
AFTER UPDATE 
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Cuentas_Fiados (IdCliente, IdVenta, SaldoPendiente, Estado)
    SELECT IdCliente, IdVenta, TotalVenta, 'Pendiente'
    FROM inserted
    WHERE EstadoVenta = 'Credito' AND TotalVenta > 0;
END;
GO


CREATE TRIGGER trg_PagarAbono
ON Abonos
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE cf
    SET cf.SaldoPendiente = cf.SaldoPendiente - a.TotalAbonado
    FROM Cuentas_Fiados cf
    INNER JOIN (
        SELECT IdCuenta, SUM(MontoPagado) AS TotalAbonado
        FROM inserted
        GROUP BY IdCuenta
    ) a ON cf.IdCuenta = a.IdCuenta;

    UPDATE Cuentas_Fiados
    SET Estado = 'Pagado'
    WHERE SaldoPendiente <= 0 AND Estado = 'Pendiente';
END;
GO


CREATE VIEW vw_LibroDeFiados AS
SELECT 
    c.Alias_Apodo AS Cliente,
    v.FechaVenta,
    v.TipoComprobante,
    cf.SaldoPendiente AS DeudaSoles,
    cf.Estado
FROM Cuentas_Fiados cf
INNER JOIN Clientes c ON cf.IdCliente = c.IdCliente
INNER JOIN Ventas v ON cf.IdVenta = v.IdVenta
WHERE cf.Estado = 'Pendiente';
GO

CREATE VIEW vw_StockActual AS
SELECT 
    c.NombreCategoria,
    p.NombreProducto,
    p.Stock,
    p.UnidadMedida,
    p.PrecioVenta
FROM Productos p
INNER JOIN Categorias c ON p.IdCategoria = c.IdCategoria;
GO

CREATE VIEW vw_ArqueoCajaHoy AS
SELECT 
    'Ventas al Contado' AS Concepto,
    ISNULL(SUM(TotalVenta), 0) AS Ingreso_Real
FROM Ventas 
WHERE EstadoVenta = 'Contado' AND CAST(FechaVenta AS DATE) = CAST(GETDATE() AS DATE)
UNION ALL
SELECT 
    'Recaudación de Fiados (Abonos)' AS Concepto,
    ISNULL(SUM(MontoPagado), 0) AS Ingreso_Real
FROM Abonos 
WHERE CAST(FechaAbono AS DATE) = CAST(GETDATE() AS DATE);
GO

INSERT INTO Categorias (NombreCategoria) VALUES 
('Abarrotes'), ('Limpieza y Aseo'), ('Especias y Condimentos'), ('Lácteos y Derivados');
GO

INSERT INTO Proveedores (RUC, RazonSocial) VALUES 
('20453668631', 'DISTRIBUCIONES DON TEO S.A.C.'),
('20119546851', 'CORPORACION ADC S.A.C.'),
('20615249557', 'DISTRIBUIDORA SOL DEL VALLE S.A.C.'),
('20100093830', 'PANADERIA SAN JORGE S.A.');
GO

INSERT INTO Clientes (Alias_Apodo) VALUES 
('Ivana'), ('María Rodas'), ('Modesta'), ('María (Otra)');
GO

INSERT INTO Productos (NombreProducto, IdCategoria, PrecioVenta, UnidadMedida, Stock) VALUES 
('Mayonesa Doypack 95gr', 1, 3.50, 'Unidad', 20),
('Aceite Cocinero 900ml', 1, 9.50, 'Unidad', 10), 
('Lavavajillas Sapolio 500ml', 2, 6.00, 'Unidad', 5),
('Spaghetti San Jorge 500g', 1, 3.00, 'Unidad', 50),
('Canela (Porción)', 3, 4.00, 'Unidad', 100),
('Clavo de Olor (Porción)', 3, 1.00, 'Unidad', 100),
('Pimienta (Porción)', 3, 2.00, 'Unidad', 100),
('Comino (Porción)', 3, 2.00, 'Unidad', 100),
('Detergente Ace', 2, 3.00, 'Unidad', 30),
('Galleta', 1, 1.60, 'Unidad', 40),
('Pasta Dental Colgate', 2, 5.00, 'Unidad', 15),
('Avena', 1, 4.00, 'Unidad', 20),
('Azúcar', 1, 12.00, 'Unidad', 50),
('Limpiador Ace Pato', 2, 2.40, 'Unidad', 20),
('Poet', 2, 3.00, 'Unidad', 15),
('Jabón', 2, 2.00, 'Unidad', 25),
('Chufla', 1, 3.00, 'Unidad', 10),
('Papel Higiénico', 2, 11.00, 'Unidad', 30),
('Champú', 2, 15.00, 'Unidad', 12),
('Atún Filete', 1, 7.00, 'Unidad', 24),
('Arroz', 1, 4.00, 'Unidad', 50),
('Linaza', 1, 1.00, 'Unidad', 20);
GO

-- SE SIMULO UNA COMPRA DE LOGÍSTICA
INSERT INTO Compras (IdProveedor, TipoComprobante, NumComprobante, CondicionPago) VALUES 
(3, 'Factura', 'B002-00039404', 'Contado'); 

INSERT INTO Detalle_Compras (IdCompra, IdProducto, Cantidad, CostoUnitario, Subtotal) VALUES 
(1, 2, 72, 8.16, 587.52), 
(1, 3, 36, 5.23, 188.28); 
GO

--Ventas 

-- VENTA 1: IVANA 
INSERT INTO Ventas (IdCliente, EstadoVenta, TipoComprobante) VALUES (1, 'Credito', 'Ticket Interno');
INSERT INTO Detalle_Ventas (IdVenta, IdProducto, Cantidad, PrecioUnitario_Venta, Subtotal) VALUES 
(1, 5, 1, 4.00, 4.00),  
(1, 6, 1, 1.00, 1.00),  
(1, 7, 1, 2.00, 2.00),  
(1, 8, 1, 2.00, 2.00),  
(1, 9, 1, 3.00, 3.00),  
(1, 10, 1, 1.60, 1.60), 
(1, 11, 1, 5.00, 5.00), 
(1, 12, 1, 4.00, 4.00), 
(1, 13, 1, 12.00, 12.00),
(1, 3, 1, 6.00, 6.00);  
GO

-- VENTA 2: MARÍA RODAS
INSERT INTO Ventas (IdCliente, EstadoVenta, TipoComprobante) VALUES (2, 'Credito', 'Ticket Interno');
INSERT INTO Detalle_Ventas (IdVenta, IdProducto, Cantidad, PrecioUnitario_Venta, Subtotal) VALUES 
(2, 3, 1, 6.00, 6.00),  
(2, 14, 1, 2.40, 2.40), 
(2, 11, 1, 5.50, 5.50), 
(2, 2, 1, 9.50, 9.50);  
GO

-- VENTA 3: MODESTA
INSERT INTO Ventas (IdCliente, EstadoVenta, TipoComprobante) VALUES (3, 'Credito', 'Ticket Interno');
INSERT INTO Detalle_Ventas (IdVenta, IdProducto, Cantidad, PrecioUnitario_Venta, Subtotal) VALUES 
(3, 15, 1, 3.00, 3.00), 
(3, 16, 1, 2.00, 2.00), 
(3, 17, 1, 3.00, 3.00), 
(3, 18, 1, 11.00, 11.00),
(3, 3, 1, 6.00, 6.00),  
(3, 2, 1, 9.50, 9.50);  
GO

-- VENTA 4: MARÍA ( OTRA PERSONA QUE SE LLAMA MARIA)
INSERT INTO Ventas (IdCliente, EstadoVenta, TipoComprobante) VALUES (4, 'Credito', 'Ticket Interno');
INSERT INTO Detalle_Ventas (IdVenta, IdProducto, Cantidad, PrecioUnitario_Venta, Subtotal) VALUES 
(4, 19, 1, 15.00, 15.00),
(4, 2, 1, 9.50, 9.50),  
(4, 1, 1, 3.50, 3.50),  
(4, 20, 1, 7.00, 7.00), 
(4, 21, 1, 4.00, 4.00), 
(4, 22, 1, 1.00, 1.00); 
GO

SELECT * FROM vw_LibroDeFiados;
GO

SELECT * FROM vw_StockActual ORDER BY Stock DESC;
GO

SELECT * FROM vw_ArqueoCajaHoy;
GO
