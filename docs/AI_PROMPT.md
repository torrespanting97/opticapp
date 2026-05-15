# Template-aware AI extraction prompt

The exact prompt sent to Groq / Gemini is preserved verbatim from the
production HTML so OCR results stay bit-identical between the legacy
single-page app and the new Flutter client.

Source of truth: `supabase/functions/extract-receipt/prompt.ts`.

The returned JSON contract — used by the Flutter `OrderForm` to auto-fill
the *Nueva* screen — is:

```jsonc
{
  // patient
  "nombre":"", "tel":"", "edad":"", "calle":"", "entre":"",
  "colonia":"", "municipio":"", "optom":"", "ref":"", "fecha":"",

  // Rx
  "od_esf":"", "od_cyl":"", "od_eje":"", "od_add":"",
  "oi_esf":"", "oi_cyl":"", "oi_eje":"", "oi_add":"",
  "dip":"",   "alt":"",

  // previous / current
  "ant_od":"", "ant_oi":"", "act_od":"", "act_oi":"",

  // frame & lens
  "armazon":"", "medidas":"", "tipo_vision":"",
  "material":"",   // BLANCO | POLI | HI
  "diseno":"",     // MONO | INVISIBLE | PROGRESIVO
  "foto": false,
  "ar":"",         // AR | AR_BLUE | NO

  // medical
  "diab": false, "pres": false,

  // payment
  "costo":"", "anticipo":"", "fpago":"", "semanal":"",
  "entrega":"", "diapago":"",

  // lab / promoter
  "lab":"", "prom":""
}
```

See the prompt body in `supabase/functions/extract-receipt/prompt.ts`.
