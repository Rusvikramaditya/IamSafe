import dayjs from 'dayjs';
import utc from 'dayjs/plugin/utc';
import timezone from 'dayjs/plugin/timezone';

dayjs.extend(utc);
dayjs.extend(timezone);

/**
 * Get the current time in the given IANA timezone.
 * Returns a dayjs object anchored to that timezone.
 */
export function nowInTimezone(tz: string): dayjs.Dayjs {
  return dayjs().tz(tz);
}

/**
 * Get today's date string (YYYY-MM-DD) in the given IANA timezone.
 */
export function todayInTimezone(tz: string): string {
  return dayjs().tz(tz).format('YYYY-MM-DD');
}

/**
 * Check whether the given IANA timezone string is valid.
 */
export function isValidTimezone(tz: string): boolean {
  try {
    Intl.DateTimeFormat(undefined, { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

export { dayjs };
