import { supabase } from '../lib/supabase.js';

const DEFAULT_TURN_MINUTES = 90;
const DEFAULT_SLOT_INTERVAL = 15;

function timeToMinutes(timeStr) {
  const [h, m] = timeStr.split(':').map(Number);
  return h * 60 + m;
}

function minutesToTime(minutes) {
  const h = Math.floor(minutes / 60).toString().padStart(2, '0');
  const m = (minutes % 60).toString().padStart(2, '0');
  return `${h}:${m}`;
}

function formatLabel(timeStr) {
  const [h, m] = timeStr.split(':').map(Number);
  const period = h >= 12 ? 'PM' : 'AM';
  const h12 = h % 12 || 12;
  return `${h12}:${m.toString().padStart(2, '0')} ${period}`;
}

function getTurnMinutes(partySize, turnTimes) {
  const match = turnTimes.find(t => partySize >= t.min && partySize <= t.max);
  if (!match) {
    console.warn(`[availability] No turn time configured for party size ${partySize}. Using ${DEFAULT_TURN_MINUTES}min fallback.`);
    return DEFAULT_TURN_MINUTES;
  }
  return match.minutes;
}

function computeSlots(windows, partySize, partyTurnMinutes, turnTimes, bookings, totalCovers, sameDayCutoffMinutes) {
  const seen = new Set();
  const slots = [];

  for (const w of windows) {
    let t = w.open;
    while (t + partyTurnMinutes <= w.close) {
      if (sameDayCutoffMinutes !== null && t < sameDayCutoffMinutes) {
        t += w.interval;
        continue;
      }

      let bookedCovers = 0;
      for (const b of bookings) {
        const bStart = timeToMinutes(b.reservation_time);
        const bEnd = bStart + getTurnMinutes(b.party_size, turnTimes);
        if (bStart <= t && t < bEnd) bookedCovers += b.party_size;
      }

      const remaining = totalCovers - bookedCovers;
      const timeStr = minutesToTime(t);

      if (!seen.has(timeStr) && remaining >= partySize) {
        seen.add(timeStr);
        slots.push({ time: timeStr, label: formatLabel(timeStr), remaining_covers: remaining });
      }

      t += w.interval;
    }
  }

  return slots.sort((a, b) => a.time.localeCompare(b.time));
}

export async function getAvailableSlots(businessId, date, partySize) {
  if (!businessId || !date || partySize < 1) return [];

  // Step 1: Business rules validation
  const { data: business, error: bizError } = await supabase
    .from('businesses')
    .select('booking_rules, active')
    .eq('id', businessId)
    .single();

  if (bizError || !business?.active) return [];

  const rules = business.booking_rules ?? {};
  const maxOnlineParty = rules.max_online_party_size ?? Infinity;
  const advanceDays = rules.advance_window_days ?? 90;
  const sameDayCutoffHours = rules.same_day_cutoff_hours ?? 1;

  if (partySize > maxOnlineParty) return [];

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const requestedDate = new Date(date + 'T00:00:00');
  const daysOut = Math.round((requestedDate - today) / 86400000);

  if (daysOut < 0 || daysOut > advanceDays) return [];

  let sameDayCutoffMinutes = null;
  if (daysOut === 0) {
    const cutoff = new Date(Date.now() + sameDayCutoffHours * 3600000);
    sameDayCutoffMinutes = cutoff.getHours() * 60 + cutoff.getMinutes();
  }

  const dayOfWeek = requestedDate.getDay();

  // Steps 2–6: parallel queries
  const [closureRes, periodsRes, hoursRes, turnTimesRes, tablesRes, coverageRes] = await Promise.all([
    // Step 2: Closure range overlap (multi-day closures included)
    supabase
      .from('business_closures')
      .select('id')
      .eq('business_id', businessId)
      .lte('closure_date', date)
      .gte('closure_end_date', date)
      .limit(1),

    // Step 3a: Service periods for this business
    supabase
      .from('service_periods')
      .select('days_of_week, open_time, close_time, slot_interval_minutes')
      .eq('business_id', businessId)
      .eq('active', true),

    // Step 3b: Operating hours fallback (one row per day)
    supabase
      .from('operating_hours')
      .select('open_time, close_time')
      .eq('business_id', businessId)
      .eq('day_of_week', dayOfWeek)
      .maybeSingle(),

    // Step 4: Turn times for all party sizes (small table, build map once)
    supabase
      .from('turn_times')
      .select('min_covers, max_covers, turn_minutes')
      .eq('business_id', businessId),

    // Step 5: Active restaurant tables for total cover count
    supabase
      .from('restaurant_tables')
      .select('covers')
      .eq('business_id', businessId)
      .eq('active', true),

    // Step 6: Existing booking coverage via SECURITY DEFINER RPC
    supabase.rpc('get_slot_coverage', { p_business_id: businessId, p_date: date }),
  ]);

  // Step 2: Closure check — any overlap returns empty
  if (closureRes.error || closureRes.data?.length > 0) return [];

  // Step 3: Determine time windows — service periods take priority over operating hours
  const activePeriods = (periodsRes.data ?? []).filter(p => p.days_of_week.includes(dayOfWeek));
  let windows;

  if (activePeriods.length > 0) {
    windows = activePeriods.map(p => ({
      open: timeToMinutes(p.open_time),
      close: timeToMinutes(p.close_time),
      interval: p.slot_interval_minutes,
    }));
  } else if (hoursRes.data) {
    windows = [{
      open: timeToMinutes(hoursRes.data.open_time),
      close: timeToMinutes(hoursRes.data.close_time),
      interval: DEFAULT_SLOT_INTERVAL,
    }];
  } else {
    return [];
  }

  // Step 4: Turn times lookup map
  const turnTimes = (turnTimesRes.data ?? []).map(r => ({
    min: r.min_covers,
    max: r.max_covers,
    minutes: r.turn_minutes,
  }));
  const partyTurnMinutes = getTurnMinutes(partySize, turnTimes);

  // Step 5: Total simultaneous capacity
  const totalCovers = (tablesRes.data ?? []).reduce((sum, t) => sum + t.covers, 0);
  if (totalCovers === 0) return [];

  // Step 6: Existing bookings from RPC (reservation_time + party_size only, no guest PII)
  const bookings = coverageRes.data ?? [];

  // Step 7: Generate available slots across all windows
  return computeSlots(windows, partySize, partyTurnMinutes, turnTimes, bookings, totalCovers, sameDayCutoffMinutes);
}
