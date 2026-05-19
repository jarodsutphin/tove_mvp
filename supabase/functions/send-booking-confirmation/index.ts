import { createClient } from 'jsr:@supabase/supabase-js@2'

// ── Types ─────────────────────────────────────────────────────────────────────

interface WebhookPayload {
  type: string
  table: string
  schema: string
  record: BookingRecord
}

interface BookingRecord {
  id: string
  business_id: string
  guest_id: string
  booking_type: string
  status: string
  reservation_date: string | null
  reservation_time: string | null
  party_size: number | null
  special_occasion: string | null
  occasion_notes: string | null
}

interface Business {
  name: string
  address: string
  phone: string | null
  brand_config: {
    logo_url?: string
    primary_color?: string
    accent_color?: string
    hours_display?: string
    confirmation_email_tone?: string
  }
}

interface Guest {
  first_name: string
  last_name: string
  email: string
}

// ── Formatters ────────────────────────────────────────────────────────────────

function formatDate(dateStr: string): string {
  const [year, month, day] = dateStr.split('-').map(Number)
  const date = new Date(Date.UTC(year, month - 1, day))
  return date.toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
    timeZone: 'UTC',
  })
}

function formatTime(timeStr: string): string {
  const [hStr, mStr] = timeStr.split(':')
  const h = parseInt(hStr, 10)
  const m = parseInt(mStr, 10)
  const period = h >= 12 ? 'PM' : 'AM'
  const hour = h % 12 || 12
  const min = m > 0 ? `:${String(m).padStart(2, '0')}` : ''
  return `${hour}${min} ${period}`
}

// ── Email template ────────────────────────────────────────────────────────────

function buildEmailHtml(params: {
  guestFirstName: string
  businessName: string
  businessAddress: string
  businessPhone: string | null
  hoursDisplay: string
  formattedDate: string
  formattedTime: string
  partySize: number
  primaryColor: string
  accentColor: string
  logoUrl: string | null
  specialOccasion: string | null
}): string {
  const {
    guestFirstName, businessName, businessAddress, businessPhone,
    hoursDisplay, formattedDate, formattedTime, partySize,
    primaryColor, accentColor, logoUrl, specialOccasion,
  } = params

  const logoHtml = logoUrl
    ? `<img src="${logoUrl}" alt="${businessName}" style="height:40px;max-width:180px;object-fit:contain;display:block;">`
    : `<span style="font-size:20px;font-weight:600;color:#ffffff;">${businessName}</span>`

  const partySizeLabel = partySize === 1 ? '1 guest' : `${partySize} guests`

  const occasionRow = specialOccasion
    ? `<tr>
        <td style="padding:10px 0 2px;border-top:1px solid #e2e8f0;">
          <span style="font-size:11px;font-weight:600;color:#64748b;text-transform:uppercase;letter-spacing:0.06em;">Occasion</span><br>
          <span style="font-size:15px;font-weight:500;color:#1e293b;line-height:1.4;">${specialOccasion}</span>
        </td>
      </tr>`
    : ''

  const phoneHtml = businessPhone
    ? `<p style="margin:2px 0 0;font-size:13px;color:#64748b;">${businessPhone}</p>`
    : ''

  const hoursHtml = hoursDisplay
    ? `<p style="margin:2px 0 0;font-size:13px;color:#64748b;">${hoursDisplay}</p>`
    : ''

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>Reservation Confirmed — ${businessName}</title>
</head>
<body style="margin:0;padding:0;background-color:#f1f5f9;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;">

  <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background-color:#f1f5f9;padding:40px 16px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="max-width:520px;">

          <!-- Header bar -->
          <tr>
            <td style="background-color:${primaryColor};padding:28px 32px;border-radius:12px 12px 0 0;">
              ${logoHtml}
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="background-color:#ffffff;padding:32px 32px 0;border-left:1px solid #e2e8f0;border-right:1px solid #e2e8f0;">

              <!-- Heading -->
              <p style="margin:0 0 4px;font-size:12px;font-weight:600;color:#64748b;text-transform:uppercase;letter-spacing:0.08em;">Reservation Confirmed</p>
              <h1 style="margin:0 0 24px;font-size:24px;font-weight:700;color:#0f172a;line-height:1.25;">You're all set, ${guestFirstName}.</h1>

              <!-- Booking summary card -->
              <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background-color:#f8fafc;border-radius:8px;padding:4px 20px 12px;">
                <tr>
                  <td style="padding:12px 0 10px;border-bottom:1px solid #e2e8f0;">
                    <span style="font-size:11px;font-weight:600;color:#64748b;text-transform:uppercase;letter-spacing:0.06em;">Date</span><br>
                    <span style="font-size:15px;font-weight:500;color:#1e293b;line-height:1.4;">${formattedDate}</span>
                  </td>
                </tr>
                <tr>
                  <td style="padding:10px 0;border-bottom:1px solid #e2e8f0;">
                    <span style="font-size:11px;font-weight:600;color:#64748b;text-transform:uppercase;letter-spacing:0.06em;">Time</span><br>
                    <span style="font-size:15px;font-weight:500;color:#1e293b;line-height:1.4;">${formattedTime}</span>
                  </td>
                </tr>
                <tr>
                  <td style="padding:10px 0${specialOccasion ? ';border-bottom:1px solid #e2e8f0;' : ''}">
                    <span style="font-size:11px;font-weight:600;color:#64748b;text-transform:uppercase;letter-spacing:0.06em;">Party size</span><br>
                    <span style="font-size:15px;font-weight:500;color:#1e293b;line-height:1.4;">${partySizeLabel}</span>
                  </td>
                </tr>
                ${occasionRow}
              </table>

              <!-- Restaurant info -->
              <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="margin-top:24px;">
                <tr>
                  <td>
                    <p style="margin:0 0 4px;font-size:14px;font-weight:600;color:#0f172a;">${businessName}</p>
                    <p style="margin:0;font-size:13px;color:#64748b;">${businessAddress}</p>
                    ${phoneHtml}
                    ${hoursHtml}
                  </td>
                </tr>
              </table>

            </td>
          </tr>

          <!-- Divider + footer -->
          <tr>
            <td style="background-color:#ffffff;padding:24px 32px 32px;border-left:1px solid #e2e8f0;border-right:1px solid #e2e8f0;border-bottom:1px solid #e2e8f0;border-radius:0 0 12px 12px;text-align:center;">
              <hr style="border:none;border-top:1px solid #e2e8f0;margin:0 0 24px;">
              <p style="margin:0 0 6px;font-size:12px;color:#94a3b8;">Need to make changes? Visit your Tove account anytime.</p>
              <a href="https://tove.app/profile" style="font-size:12px;color:${accentColor};text-decoration:underline;">Manage reservation</a>
              <p style="margin:20px 0 0;font-size:11px;color:#cbd5e1;">Powered by Tove</p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>

</body>
</html>`
}

// ── Handler ───────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  try {
    const payload = await req.json() as WebhookPayload

    if (payload.type !== 'INSERT' || payload.table !== 'bookings') {
      return new Response('skipped: not a bookings insert', { status: 200 })
    }

    const booking = payload.record

    if (booking.booking_type !== 'reservation' || booking.status !== 'confirmed') {
      return new Response('skipped: not a confirmed reservation', { status: 200 })
    }

    if (!booking.reservation_date || !booking.reservation_time || !booking.party_size) {
      return new Response('skipped: missing required reservation fields', { status: 200 })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Idempotency guard — webhook delivery is at-least-once
    const { data: existingLog } = await supabase
      .from('email_log')
      .select('id')
      .eq('booking_id', booking.id)
      .eq('email_type', 'booking_confirmation')
      .maybeSingle()

    if (existingLog) {
      return new Response('skipped: confirmation already sent', { status: 200 })
    }

    // Fetch business and guest in parallel
    const [businessRes, guestRes] = await Promise.all([
      supabase
        .from('businesses')
        .select('name, address, phone, brand_config')
        .eq('id', booking.business_id)
        .single(),
      supabase
        .from('guests')
        .select('first_name, last_name, email')
        .eq('id', booking.guest_id)
        .single(),
    ])

    if (businessRes.error) throw new Error(`business fetch: ${businessRes.error.message}`)
    if (guestRes.error)   throw new Error(`guest fetch: ${guestRes.error.message}`)

    const business = businessRes.data as Business
    const guest    = guestRes.data as Guest
    const brand    = business.brand_config ?? {}

    const primaryColor = brand.primary_color  ?? '#1a5b56'
    const accentColor  = brand.accent_color   ?? '#ff5710'
    const hoursDisplay = brand.hours_display  ?? ''
    const logoUrl      = brand.logo_url       ?? null

    const html    = buildEmailHtml({
      guestFirstName:  guest.first_name,
      businessName:    business.name,
      businessAddress: business.address,
      businessPhone:   business.phone ?? null,
      hoursDisplay,
      formattedDate:   formatDate(booking.reservation_date),
      formattedTime:   formatTime(booking.reservation_time),
      partySize:       booking.party_size,
      primaryColor,
      accentColor,
      logoUrl,
      specialOccasion: booking.special_occasion ?? null,
    })

    const subject = `Your reservation at ${business.name} is confirmed`

    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')!}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from:    `${business.name} via Tove <onboarding@resend.dev>`,
        to:      guest.email,
        subject,
        html,
      }),
    })

    const resendData = await resendRes.json()

    // Log the send — non-fatal if this insert fails
    await supabase.from('email_log').insert({
      business_id:       booking.business_id,
      guest_id:          booking.guest_id,
      booking_id:        booking.id,
      email_type:        'booking_confirmation',
      subject,
      resend_message_id: resendData.id ?? null,
      status:            resendRes.ok ? 'sent' : 'failed',
    })

    if (!resendRes.ok) {
      throw new Error(`Resend error ${resendRes.status}: ${JSON.stringify(resendData)}`)
    }

    return new Response(
      JSON.stringify({ success: true, resend_id: resendData.id }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    console.error('[send-booking-confirmation]', err)
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
})
