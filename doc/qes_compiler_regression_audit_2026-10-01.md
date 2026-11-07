# Auditoría de regresiones del compilador usadas por QES

Fecha: 2026-10-01. Plataforma verificada: Windows, GCC, V nativo.

## Cambios examinados

La integración `fc78768782` del 25 de septiembre incorporó 2,473 archivos
modificados. Se rastrearon los cambios relevantes para los fallos observados,
mediante historial, blame, pruebas del lanzador y reproducciones independientes.
Esta revisión no equivale a certificar todos los cambios de esa integración.

- `2a7447b5e5`: activó V3 como compilador por defecto el 13 de septiembre.
  Expuso dos fallos de contexto en reflexión y constructores genéricos.
- Antecedentes del código de V3: `1188128ebe` del 23 de julio añadió la
  referencia explícita al tipo de main; `9ed23df0c4` del 28 de julio añadió
  la validación anticipada de reflexión. El historial localiza esos cambios
  antes de la activación de V3 por defecto; no se atribuyen al último merge
  como si hubieran sido escritos por primera vez allí.
- `c1f64fbc8a`: introdujo una carpeta temporal aleatoria para el compilador
  de compatibilidad en Windows sin HOME. Cada invocación reinstalaba el fallback.
- `63c91a6af0`: deshabilitó la selección de tests JavaScript de V3. El lanzador
  reutilizaba ese filtro al interpretar resultados del compilador V 0.5.2,
  que sí ejecuta esos tests.
- `c53eca42a4`: retiró intencionalmente V_FALLBACK_CC_ARGS de makev.bat.
  Una prueba seguía exigiendo esa variable eliminada.

## Correcciones verificables

1. Caché persistente en LOCALAPPDATA/v/v1-fallback-private. Se crea con permisos
   explícitos del usuario y se valida con el control de ACL existente.
   La prueba inicial midió 83.416 segundos con instalación y 2.483 al reutilizarla.
   Esa comparación incluye instalación; no mide una mejora del algoritmo compilador.
2. La alternativa temporal también usa una DACL protegida. Windows ignora el
   modo POSIX 0700 de mkdir. Un nombre aleatorio por sí solo no evita heredar ACL.
   La creación distingue una carpeta nueva de una colisión existente.
3. La clasificación de salidas del fallback conserva la semántica de tests JS
   de V 0.5.2. El filtro que mantiene deshabilitado el backend JS de V3 no cambia.
4. La validación anticipada de fuentes de reflexión aplaza las variables hasta
   tener el ámbito de la función y la rama de compilación seleccionada.
5. Los constructores con una referencia explícita main.Input recuperan los
   campos mediante el resolvedor de declaraciones. El mapa de tipos guarda Input
   sin main.; consultar ese mapa directamente omitía arrays y mapas implícitos.
   Con otro Input en un módulo importado, esto producía tamaños de elementos
   inválidos y datos corruptos. Se corrigen las rutas de valor, heap y array fijo.

La prueba de makev ahora exige las rutas absolutas de TCC en ambos pasos reales
que compilan V, y la ausencia del ajuste retirado. No se restaura esa variable.

## Reproducción y pruebas

La reproducción portable está en:

- vlib/v/compiler_tests/generic_main_defaults_test.v
- vlib/v/compiler_tests/testdata/generic_main_defaults/main.vv
- vlib/v/compiler_tests/testdata/generic_main_defaults/factory.v.txt

Usa un Input en main y otro en factory, constructores genéricos de valor y heap,
un constructor con array fijo, arrays de estructuras, mapas y JSON. Se ejecuta
con el compilador nuevo, sin fallback, en modo normal y serial. Hay controles
negativos para fuentes de reflexión incompatibles.

El mismo fallo se reprodujo con las estructuras de entrada reales de QES.
Antes de corregir los constructores, un ask esperado de 5 llegaba como basura
numérica y se omitía la inicialización de requests en el C generado.
Renombrar el Input importado hizo desaparecer el fallo, aislando la colisión.

Resultados del lanzador: cuatro tests ejecutados, 67 asserts, todos aprobados.
La prueba C de ACL aprobó creación y reutilización del directorio privado.
Los dos tests nuevos aprobaron: los casos de valor, heap, array fijo y JSON
corrieron en modo normal y serial; los dos controles inválidos fueron rechazados
por el checker. Son 32 asserts dentro de los programas de reproducción y 12
checks del harness. La entrada de ejemplo de QES aprobó siete comparaciones
exactas, incluyendo bid, ask, saldo, riesgo y timestamps de 64 bits.
La reconstrucción del compilador activo terminó con éxito.

## Límite de cobertura

La suite extensa de diagnósticos tiene discrepancias entre fixtures actuales y
la versión estable de compatibilidad usada para suites heredadas. Se observaron,
entre otras, diferencias en diagnósticos de sort de arrays. No se modificaron
salidas esperadas para ocultarlas y no se declara verde la suite completa.

No se cambiaron las modificaciones previas ajenas en AGENTS.md y .gitignore.
No hay cambios de API pública ni nuevos flags del compilador.