DECLARE @Fecha DATE = @pFecha;
DECLARE @Demandante NVARCHAR(200) = @pDemandante;

;WITH Expedientes AS (
    SELECT DISTINCT LTRIM(RTRIM(EXPEDIENTE)) AS EXPEDIENTE
    FROM INFORME_JURIDICO
    WHERE CAST(FECHA_ULTIMA_ACTUACION AS DATE) = @Fecha
      AND DEMANDANTE = @Demandante
      AND ESTADO_ACTUAL_DASH = 'ACTIVO'
      AND ETAPA NOT IN ('ASIGNACION', 'RENUNCIA PODER')
),
BaseRaw AS (
    SELECT
        i.ID_EXPEDIENTE,
        LTRIM(RTRIM(i.EXPEDIENTE)) AS EXPEDIENTE,
        LTRIM(RTRIM(i.DEMANDADO1_DOCUMENTO)) AS DEMANDADO1_DOCUMENTO,
        LTRIM(RTRIM(i.CLASE_PROCESO))        AS CLASE_PROCESO,
        i.RADICADO_CORTO,
        i.JUZGADO_ACTUAL,
        i.CIUDAD_JUZGADO_ACTUAL,
        a.PAGARES,
        p.PAGARES_STRIPPED,
        ROW_NUMBER() OVER (
            PARTITION BY LTRIM(RTRIM(i.EXPEDIENTE))
            ORDER BY i.FECHA_ULTIMA_ACTUACION DESC, i.ID_EXPEDIENTE DESC
        ) AS pick_rn
    FROM INFORME_JURIDICO i
    INNER JOIN Expedientes e
        ON LTRIM(RTRIM(i.EXPEDIENTE)) = e.EXPEDIENTE
    OUTER APPLY (
        SELECT
            STRING_AGG(t.token, ', ') WITHIN GROUP (ORDER BY t.token) AS PAGARES
        FROM (
            SELECT DISTINCT s.value AS token
            FROM (VALUES
                (NULLIF(LTRIM(RTRIM(i.PAGARE1_OBLIGACION)), '')),
                (NULLIF(LTRIM(RTRIM(i.PAGARE2_OBLIGACION)), '')),
                (NULLIF(LTRIM(RTRIM(i.PAGARE3_OBLIGACION)), '')),
                (NULLIF(LTRIM(RTRIM(i.PAGARE4_OBLIGACION)), ''))
            ) v(raw)
            CROSS APPLY (
                SELECT REPLACE(
                           REPLACE(
                               REPLACE(ISNULL(v.raw, ''), ' - ', ','),
                           '-', ','),
                       '–', ',') AS norm
            ) n
            CROSS APPLY (
                SELECT value
                FROM STRING_SPLIT(
                    CAST(REPLACE(n.norm, ' ', '') AS nvarchar(max)),
                    ','
                )
            ) s
            WHERE s.value <> ''
        ) t
    ) a
    OUTER APPLY (
        SELECT
          REPLACE(
            REPLACE(
              REPLACE(
                REPLACE(
                  REPLACE(ISNULL(a.PAGARES, ''), ' ', ''),
                CHAR(9), ''),
              CHAR(10), ''),
            CHAR(13), ''),
          ',', '') AS PAGARES_STRIPPED
    ) p
),
Base AS (
    SELECT *
    FROM BaseRaw
    WHERE pick_rn = 1
      AND NULLIF(LTRIM(RTRIM(CONVERT(NVARCHAR(50), ID_EXPEDIENTE))), '') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(DEMANDADO1_DOCUMENTO)), '') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(CLASE_PROCESO)), '') IS NOT NULL
      AND NULLIF(PAGARES_STRIPPED, '') IS NOT NULL
),
ActuacionesAgrupadas AS (
    SELECT
        AAE.expedienteId,
        ATE.nombreTipoEtapa,
        ASU.nombreSubEtapa,
        AAE.fecActuacion,
        AAE.observacionP1,
        ROW_NUMBER() OVER(
            PARTITION BY AAE.expedienteId, ATE.nombreTipoEtapa, ASU.nombreSubEtapa, AAE.observacionP1
            ORDER BY AAE.fecActuacion ASC
        ) AS rn
    FROM APLI_ACTUACIONES_EXPEDIENTES AAE
    JOIN APLI_SUBETAPAS   ASU ON AAE.subEtapaId = ASU.idSubEtapa
    JOIN APLI_TIPO_ETAPAS ATE ON ASU.tipoEtapaId = ATE.idTipoEtapa
    WHERE
        ASU.nombreSubEtapa <> 'acta de reparto'
        AND LTRIM(RTRIM(AAE.nombreActuacionExpediente)) <> ''
        AND AAE.fecActuacion IS NOT NULL
)
SELECT
    b.ID_EXPEDIENTE,
    b.EXPEDIENTE,
    b.DEMANDADO1_DOCUMENTO,
    b.CLASE_PROCESO,
    b.PAGARES,
    b.RADICADO_CORTO,
    b.JUZGADO_ACTUAL,
    b.CIUDAD_JUZGADO_ACTUAL,
    a.nombreTipoEtapa,
    a.nombreSubEtapa,
    CONVERT(VARCHAR(10), a.fecActuacion, 103) AS fecActuacion,
    a.observacionP1
FROM Base b
LEFT JOIN ActuacionesAgrupadas a
  ON a.expedienteId = b.ID_EXPEDIENTE
 AND a.rn = 1
ORDER BY b.ID_EXPEDIENTE, a.fecActuacion ASC;
