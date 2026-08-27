import { useMemo } from 'react';
import { useClockVersion, useRecordVersion } from '../state/researchStore';

export function useRecord<T>(read: () => T, deps: unknown[] = []): T {
  const record = useRecordVersion();

  return useMemo(read, [record, ...deps]);
}

export function useMoment<T>(read: () => T, deps: unknown[] = []): T {
  const record = useRecordVersion();
  const clock = useClockVersion();

  return useMemo(read, [record, clock, ...deps]);
}
