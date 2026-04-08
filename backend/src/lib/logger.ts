const isProd = process.env.NODE_ENV === 'production';

type Level = 'info' | 'warn' | 'error';

type Meta = Record<string, unknown>;

function write(level: Level, message: string, meta?: Meta): void {
  if (isProd) {
    // Cloud Logging recognises the `severity` field automatically
    const severity = level === 'info' ? 'INFO' : level === 'warn' ? 'WARNING' : 'ERROR';
    process.stdout.write(
      JSON.stringify({ severity, message, ...meta, timestamp: new Date().toISOString() }) + '\n'
    );
  } else {
    const prefix = level === 'error' ? '❌' : level === 'warn' ? '⚠️ ' : 'ℹ️ ';
    const extra = meta ? ' ' + JSON.stringify(meta) : '';
    console[level === 'warn' ? 'warn' : level === 'error' ? 'error' : 'log'](
      `${prefix} ${message}${extra}`
    );
  }
}

export const logger = {
  info: (message: string, meta?: Meta) => write('info', message, meta),
  warn: (message: string, meta?: Meta) => write('warn', message, meta),
  error: (message: string, meta?: Meta) => write('error', message, meta),
};
