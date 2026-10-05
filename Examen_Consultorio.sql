-- =========================================================================
-- PROYECTO: Base de Datos - Consultorio Médico
-- OBJETIVO: Implementación de mecanismos de protección de datos personales
-- =========================================================================

CREATE DATABASE IF NOT EXISTS ConsultorioSeguro;
USE ConsultorioSeguro;

-- -------------------------------------------------------------------------
-- PARTE A: Diseño de la Base de Datos (4 a 6 tablas)
-- -------------------------------------------------------------------------

-- Tabla 1: Especialidades (Datos no personales)
CREATE TABLE Especialidades (
    id_especialidad INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL
);

-- Tabla 2: Médicos (Contiene datos personales básicos)
CREATE TABLE Medicos (
    id_medico INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    telefono VARCHAR(15),
    id_especialidad INT,
    FOREIGN KEY (id_especialidad) REFERENCES Especialidades(id_especialidad)
);

-- Tabla 3: Pacientes (Contiene datos personales y SENSIBLES)
-- Se incluye la columna 'activo' para el borrado lógico.
CREATE TABLE Pacientes (
    id_paciente INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    telefono VARCHAR(15),
    correo VARCHAR(100),
    domicilio VARCHAR(200),
    tipo_sangre VARCHAR(5),       -- Dato sensible
    padecimientos TEXT,           -- Dato sensible
    fecha_registro DATE DEFAULT (CURRENT_DATE),
    activo BOOLEAN DEFAULT 1      -- 1 = Activo, 0 = Inactivo (Borrado lógico)
);

-- Tabla 4: Citas (Relaciona pacientes y médicos)
CREATE TABLE Citas (
    id_cita INT AUTO_INCREMENT PRIMARY KEY,
    id_paciente INT,
    id_medico INT,
    fecha_hora DATETIME NOT NULL,
    motivo VARCHAR(200),
    estatus ENUM('Programada', 'Completada', 'Cancelada') DEFAULT 'Programada',
    FOREIGN KEY (id_paciente) REFERENCES Pacientes(id_paciente),
    FOREIGN KEY (id_medico) REFERENCES Medicos(id_medico)
);

-- Insertar datos ficticios de prueba
INSERT INTO Especialidades (nombre) VALUES ('Medicina General'), ('Cardiología'), ('Pediatría');

INSERT INTO Medicos (nombre, telefono, id_especialidad) VALUES 
('Dra. Ana López', '5551234567', 1),
('Dr. Carlos Pérez', '5559876543', 2);

INSERT INTO Pacientes (nombre, telefono, correo, domicilio, tipo_sangre, padecimientos) VALUES 
('Juan Robles', '6181112233', 'juan@email.com', 'Calle 1, Ciudad', 'O+', 'Hipertensión'),
('María García', '6184445566', 'maria@email.com', 'Avenida 2, Ciudad', 'A-', 'Ninguno'),
('Luis Hernández', '6187778899', 'luis@email.com', 'Plaza 3, Ciudad', 'B+', 'Diabetes');

INSERT INTO Citas (id_paciente, id_medico, fecha_hora, motivo) VALUES 
(1, 1, '2026-09-10 10:00:00', 'Chequeo general'),
(2, 2, '2026-09-11 11:30:00', 'Revisión cardíaca');

-- -------------------------------------------------------------------------
-- PARTE B: Minimización de datos mediante Vistas
-- -------------------------------------------------------------------------

-- Vista 1: Oculta teléfono, correo, domicilio y padecimientos (datos sensibles).
CREATE VIEW Vista_Reporte_Pacientes AS
SELECT id_paciente AS matricula, nombre, fecha_registro, 
       IF(activo = 1, 'Activo', 'Inactivo') AS estatus
FROM Pacientes;

-- Vista 2: Muestra las citas sin revelar detalles médicos ni contactos del paciente.
CREATE VIEW Vista_Citas_Recepcion AS
SELECT c.id_cita, p.nombre AS paciente, m.nombre AS medico, c.fecha_hora, c.estatus
FROM Citas c
JOIN Pacientes p ON c.id_paciente = p.id_paciente
JOIN Medicos m ON c.id_medico = m.id_medico
WHERE p.activo = 1;

-- -------------------------------------------------------------------------
-- PARTE C: Usuarios y Privilegios
-- -------------------------------------------------------------------------

-- Crear usuario administrativo
CREATE USER 'admin_clinica'@'localhost' IDENTIFIED BY 'Admin_2026!';
GRANT ALL PRIVILEGES ON ConsultorioSeguro.* TO 'admin_clinica'@'localhost';

-- Crear usuario de consulta (solo vistas permitidas)
CREATE USER 'recepcionista'@'localhost' IDENTIFIED BY 'Recep_2026!';
GRANT SELECT ON ConsultorioSeguro.Vista_Reporte_Pacientes TO 'recepcionista'@'localhost';
GRANT SELECT ON ConsultorioSeguro.Vista_Citas_Recepcion TO 'recepcionista'@'localhost';
-- Se le revoca cualquier acceso directo a las tablas por seguridad.
REVOKE ALL PRIVILEGES ON ConsultorioSeguro.Pacientes FROM 'recepcionista'@'localhost';

FLUSH PRIVILEGES;

-- -------------------------------------------------------------------------
-- PARTE E: Bitácora y Disparadores
-- -------------------------------------------------------------------------

-- Tabla de Bitácora
CREATE TABLE Bitacora_Cambios (
    id_bitacora INT AUTO_INCREMENT PRIMARY KEY,
    tabla_afectada VARCHAR(50),
    id_registro INT,
    operacion VARCHAR(50),
    usuario VARCHAR(50),
    fecha_hora DATETIME DEFAULT CURRENT_TIMESTAMP,
    detalle TEXT
);

DELIMITER //

-- Trigger 1: Registrar modificaciones (Updates) en datos del paciente
CREATE TRIGGER trg_paciente_modificado
AFTER UPDATE ON Pacientes
FOR EACH ROW
BEGIN
    -- Ignorar si el update fue solo para el borrado lógico (activo a 0)
    IF OLD.activo = NEW.activo THEN
        INSERT INTO Bitacora_Cambios (tabla_afectada, id_registro, operacion, usuario, detalle)
        VALUES ('Pacientes', NEW.id_paciente, 'MODIFICACION', USER(), CONCAT('Se modificaron datos del paciente: ', NEW.nombre));
    END IF;
END //

-- Trigger 2: Registrar eliminaciones (Borrado lógico)
CREATE TRIGGER trg_paciente_borrado_logico
AFTER UPDATE ON Pacientes
FOR EACH ROW
BEGIN
    IF OLD.activo = 1 AND NEW.activo = 0 THEN
        INSERT INTO Bitacora_Cambios (tabla_afectada, id_registro, operacion, usuario, detalle)
        VALUES ('Pacientes', NEW.id_paciente, 'BORRADO LOGICO', USER(), CONCAT('Paciente dado de baja: ', NEW.nombre));
    END IF;
END //

DELIMITER ;

-- -------------------------------------------------------------------------
-- PARTE F: Procedimiento Almacenado
-- -------------------------------------------------------------------------
-- Procedimiento para actualizar el estatus de una cita de manera controlada
DELIMITER //
CREATE PROCEDURE SP_CambiarEstatusCita (
    IN p_id_cita INT,
    IN p_nuevo_estatus VARCHAR(20)
)
BEGIN
    UPDATE Citas 
    SET estatus = p_nuevo_estatus 
    WHERE id_cita = p_id_cita;
END //
DELIMITER ;

-- -------------------------------------------------------------------------
-- PARTE G: Función
-- -------------------------------------------------------------------------
-- Función para enmascarar un teléfono (ej. 6181234567 -> ******4567)
DELIMITER //
CREATE FUNCTION FN_EnmascararTelefono (telefono_real VARCHAR(15))
RETURNS VARCHAR(15)
DETERMINISTIC
BEGIN
    IF telefono_real IS NULL OR LENGTH(telefono_real) < 4 THEN
        RETURN telefono_real;
    ELSE
        RETURN CONCAT(REPEAT('*', LENGTH(telefono_real) - 4), RIGHT(telefono_real, 4));
    END IF;
END //
DELIMITER ;