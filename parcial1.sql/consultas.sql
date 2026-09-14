-- ============================================================
-- PropiedadCerca (Caso 3) - BDY1103
-- PARCIAL 1: Fundamentos de PL/SQL
-- ============================================================
-- Este script contiene 5 bloques PL/SQL independientes, cada
-- uno resolviendo uno de los puntos pedidos en la Entrega 1:
--   1) RECORD + consulta real
--   2) VARRAY para validar valores de negocio acotados
--   3) Cursor explicito CON parametros y otro SIN parametros,
--      combinados en loops anidados (edificios / unidades)
--   4) Excepciones predefinidas de Oracle (NO_DATA_FOUND y
--      TOO_MANY_ROWS) sobre una situacion real del negocio
--   5) Excepcion propia que hace cumplir RN3 (no se puede abrir
--      una solicitud de mantencion duplicada sobre la misma
--      unidad si ya existe una que no esta RESUELTA ni CANCELADA)
-- Cada bloque se ejecuta por separado (separados por "/").
-- ============================================================


-- ============================================================
-- BLOQUE 1: RECORD para la ficha completa de un contrato
-- ============================================================
-- Objetivo de negocio:
--   El equipo de administracion necesita revisar, de un solo
--   vistazo, todos los datos relevantes de un contrato: quien
--   es el arrendatario, en que unidad y edificio vive, cuanto
--   paga al mes y en que estado esta el contrato.
-- ============================================================

SET SERVEROUTPUT ON;

DECLARE

  -- ----------------------------------------------------------
  -- RECORD: agrupa los datos de la "ficha" de un contrato
  -- ----------------------------------------------------------
  TYPE t_ficha_contrato IS RECORD (
    contrato_id      contrato_arriendo.contrato_id%TYPE,
    arrendatario     arrendatario.nombre%TYPE,
    edificio         edificio.nombre%TYPE,
    numero_unidad    unidad.numero_unidad%TYPE,
    monto_mensual    contrato_arriendo.monto_mensual%TYPE,
    estado_contrato  contrato_arriendo.estado%TYPE
  );

  v_ficha t_ficha_contrato;

  -- Contrato que queremos revisar (dato de entrada del caso)
  v_contrato_id contrato_arriendo.contrato_id%TYPE := 1;

BEGIN

  -- ----------------------------------------------------------
  -- Consulta real: se hace JOIN entre contrato, arrendatario,
  -- unidad y edificio para armar la ficha completa en una sola
  -- fila, que se carga directamente en el RECORD con SELECT INTO.
  -- ----------------------------------------------------------
  SELECT ca.contrato_id,
         ar.nombre,
         ed.nombre,
         un.numero_unidad,
         ca.monto_mensual,
         ca.estado
    INTO v_ficha
    FROM contrato_arriendo ca
    JOIN arrendatario ar ON ca.arrendatario_id = ar.arrendatario_id
    JOIN unidad un        ON ca.unidad_id       = un.unidad_id
    JOIN edificio ed      ON un.edificio_id     = ed.edificio_id
   WHERE ca.contrato_id = v_contrato_id;

  DBMS_OUTPUT.PUT_LINE('=== Ficha del contrato ' || v_ficha.contrato_id || ' ===');
  DBMS_OUTPUT.PUT_LINE('Arrendatario : ' || v_ficha.arrendatario);
  DBMS_OUTPUT.PUT_LINE('Edificio     : ' || v_ficha.edificio);
  DBMS_OUTPUT.PUT_LINE('Unidad       : ' || v_ficha.numero_unidad);
  DBMS_OUTPUT.PUT_LINE('Monto mensual: $' || v_ficha.monto_mensual);
  DBMS_OUTPUT.PUT_LINE('Estado       : ' || v_ficha.estado_contrato);

END;
/


-- ============================================================
-- BLOQUE 2: VARRAY para validar estados de una solicitud
-- ============================================================
-- Objetivo de negocio:
--   Antes de guardar una SOLICITUD_MANTENCION, el sistema debe
--   verificar que el estado que se le quiere asignar sea uno de
--   los valores de negocio permitidos. Se usa un VARRAY como
--   catalogo acotado (4 estados posibles) y se valida un valor
--   correcto y uno incorrecto.
-- ============================================================

DECLARE

  -- ----------------------------------------------------------
  -- VARRAY: conjunto acotado de estados validos para una
  -- solicitud de mantencion (coincide con el CHECK de la tabla)
  -- ----------------------------------------------------------
  TYPE t_estados_solicitud IS VARRAY(4) OF VARCHAR2(15);

  v_estados_validos t_estados_solicitud := t_estados_solicitud(
    'ABIERTA', 'EN_PROCESO', 'RESUELTA', 'CANCELADA'
  );

  -- Funcion local (subprograma anidado) que recorre el VARRAY
  -- y dice si el valor recibido esta entre los permitidos.
  FUNCTION f_es_estado_valido(p_estado VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    FOR i IN 1 .. v_estados_validos.COUNT LOOP
      IF v_estados_validos(i) = p_estado THEN
        RETURN TRUE;
      END IF;
    END LOOP;
    RETURN FALSE;
  END f_es_estado_valido;

  v_estado_prueba_ok    VARCHAR2(15) := 'RESUELTA';   -- valor valido
  v_estado_prueba_malo  VARCHAR2(15) := 'PENDIENTE';  -- valor invalido (no existe para solicitudes)

BEGIN

  DBMS_OUTPUT.PUT_LINE('=== Validacion de estados con VARRAY ===');

  IF f_es_estado_valido(v_estado_prueba_ok) THEN
    DBMS_OUTPUT.PUT_LINE('"' || v_estado_prueba_ok || '" es un estado VALIDO.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('"' || v_estado_prueba_ok || '" NO es un estado valido.');
  END IF;

  IF f_es_estado_valido(v_estado_prueba_malo) THEN
    DBMS_OUTPUT.PUT_LINE('"' || v_estado_prueba_malo || '" es un estado VALIDO.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('"' || v_estado_prueba_malo || '" NO es un estado valido (rechazado).');
  END IF;

END;
/


-- ============================================================
-- BLOQUE 3: cursor SIN parametros + cursor CON parametros,
--           combinados en loops anidados
-- ============================================================
-- Objetivo de negocio:
--   Recorrer todos los edificios y, dentro de cada uno, listar
--   solo las unidades que estan DISPONIBLE para arrendar.
--
-- Por que uno lleva parametro y el otro no:
--   c_edificios no necesita parametro porque siempre recorre
--   TODOS los edificios de la empresa, sin ningun filtro que
--   dependa de un valor externo.
--   c_unidades_disponibles SI necesita parametro (p_edificio_id)
--   porque su resultado depende de "de que edificio estamos
--   hablando" en cada vuelta del loop externo: sin el parametro
--   no podriamos reutilizar el mismo cursor para cada edificio.
-- ============================================================

DECLARE

  -- ----------------------------------------------------------
  -- CURSOR SIN PARAMETROS: recorre todos los edificios
  -- ----------------------------------------------------------
  CURSOR c_edificios IS
    SELECT edificio_id, nombre
      FROM edificio
     ORDER BY edificio_id;

  -- ----------------------------------------------------------
  -- CURSOR CON PARAMETRO: unidades DISPONIBLES de un edificio
  -- ----------------------------------------------------------
  CURSOR c_unidades_disponibles(p_edificio_id edificio.edificio_id%TYPE) IS
    SELECT numero_unidad, categoria
      FROM unidad
     WHERE edificio_id = p_edificio_id
       AND estado = 'DISPONIBLE'
     ORDER BY numero_unidad;

  r_edificio  c_edificios%ROWTYPE;
  r_unidad    c_unidades_disponibles%ROWTYPE;

  v_total_disponibles NUMBER := 0;

BEGIN

  DBMS_OUTPUT.PUT_LINE('=== Unidades disponibles por edificio ===');

  -- --------------------------------------------------------
  -- LOOP EXTERNO: un edificio a la vez (cursor sin parametros)
  -- --------------------------------------------------------
  OPEN c_edificios;
  LOOP
    FETCH c_edificios INTO r_edificio;
    EXIT WHEN c_edificios%NOTFOUND;

    DBMS_OUTPUT.PUT_LINE('Edificio: ' || r_edificio.nombre);

    -- ------------------------------------------------------
    -- LOOP INTERNO: unidades disponibles de ESE edificio
    -- (cursor con parametro, se abre y cierra en cada vuelta)
    -- ------------------------------------------------------
    OPEN c_unidades_disponibles(r_edificio.edificio_id);
    LOOP
      FETCH c_unidades_disponibles INTO r_unidad;
      EXIT WHEN c_unidades_disponibles%NOTFOUND;

      DBMS_OUTPUT.PUT_LINE('   -> Unidad ' || r_unidad.numero_unidad
                            || ' (' || r_unidad.categoria || ')');
      v_total_disponibles := v_total_disponibles + 1;
    END LOOP;
    CLOSE c_unidades_disponibles;

  END LOOP;
  CLOSE c_edificios;

  DBMS_OUTPUT.PUT_LINE('=== Total de unidades disponibles en la empresa: '
                        || v_total_disponibles || ' ===');

END;
/


-- ============================================================
-- BLOQUE 4: excepciones predefinidas de Oracle
-- ============================================================
-- Situacion real 1: buscar un arrendatario que NO existe
--   -> Oracle lanza NO_DATA_FOUND porque el SELECT INTO no
--      encuentra ninguna fila.
-- Situacion real 2: buscar "el" tecnico de una especialidad
--   asumiendo que hay solo uno, cuando en realidad hay varios
--   -> Oracle lanza TOO_MANY_ROWS porque el SELECT INTO trae
--      mas de una fila.
-- ============================================================

DECLARE

  v_nombre_arrendatario  arrendatario.nombre%TYPE;
  v_id_inexistente       arrendatario.arrendatario_id%TYPE := 999;

  v_nombre_tecnico       tecnico.nombre%TYPE;
  v_especialidad         tecnico.especialidad%TYPE := 'GASFITERIA'; -- hay 2 tecnicos con esta especialidad

BEGIN

  -- --------------------------------------------------------
  -- Caso 1: arrendatario inexistente -> NO_DATA_FOUND
  -- --------------------------------------------------------
  BEGIN
    SELECT nombre
      INTO v_nombre_arrendatario
      FROM arrendatario
     WHERE arrendatario_id = v_id_inexistente;

    DBMS_OUTPUT.PUT_LINE('Arrendatario encontrado: ' || v_nombre_arrendatario);

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('No existe ningun arrendatario con id '
                            || v_id_inexistente || ' (NO_DATA_FOUND).');
  END;

  -- --------------------------------------------------------
  -- Caso 2: se esperaba un solo tecnico y hay varios -> TOO_MANY_ROWS
  -- --------------------------------------------------------
  BEGIN
    SELECT nombre
      INTO v_nombre_tecnico
      FROM tecnico
     WHERE especialidad = v_especialidad;

    DBMS_OUTPUT.PUT_LINE('Tecnico encontrado: ' || v_nombre_tecnico);

  EXCEPTION
    WHEN TOO_MANY_ROWS THEN
      DBMS_OUTPUT.PUT_LINE('Hay mas de un tecnico de especialidad '
                            || v_especialidad
                            || '; se debe elegir con un criterio adicional (TOO_MANY_ROWS).');
  END;

END;
/


-- ============================================================
-- BLOQUE 5: excepcion propia para RN3
-- ============================================================
-- RN3: un arrendatario no puede abrir una nueva solicitud de
-- mantencion para una unidad si ya tiene otra solicitud sobre
-- esa misma unidad que no esta RESUELTA ni CANCELADA.
--
-- Oracle no tiene forma de validar esto por si solo (no es una
-- restriccion de tipo, ni una PK/FK): por eso se necesita una
-- excepcion propia que se lanza cuando se detecta la condicion
-- de negocio prohibida, antes de intentar el INSERT.
-- ============================================================

DECLARE

  e_solicitud_duplicada EXCEPTION;

  v_unidad_id        unidad.unidad_id%TYPE       := 2;  -- unidad con una solicitud ABIERTA (dato de prueba)
  v_arrendatario_id  arrendatario.arrendatario_id%TYPE := 1;
  v_tipo_problema    solicitud_mantencion.tipo_problema%TYPE := 'GASFITERIA';

  v_solicitudes_abiertas NUMBER;

BEGIN

  -- ----------------------------------------------------------
  -- Contamos cuantas solicitudes de ESA unidad siguen "abiertas"
  -- (no estan RESUELTA ni CANCELADA)
  -- ----------------------------------------------------------
  SELECT COUNT(*)
    INTO v_solicitudes_abiertas
    FROM solicitud_mantencion
   WHERE unidad_id = v_unidad_id
     AND estado NOT IN ('RESUELTA', 'CANCELADA');

  IF v_solicitudes_abiertas > 0 THEN
    RAISE e_solicitud_duplicada;
  END IF;

  -- Si no hay ninguna abierta, se podria insertar la nueva solicitud:
  -- INSERT INTO solicitud_mantencion (...) VALUES (...);
  DBMS_OUTPUT.PUT_LINE('Solicitud registrada correctamente para la unidad '
                        || v_unidad_id || '.');

EXCEPTION
  WHEN e_solicitud_duplicada THEN
    DBMS_OUTPUT.PUT_LINE('No se puede crear la solicitud: la unidad '
                          || v_unidad_id
                          || ' ya tiene una solicitud sin resolver. '
                          || 'El arrendatario debe esperar su resolucion (RN3).');
END;
/
