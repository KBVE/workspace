import { create } from 'zustand';
import { installGodotBridge } from '../godot/bridge';
import { noticeById, type Notice } from '../content/content';

interface NoticeStore {
  /** The sheet being read, or null when nothing is open. */
  reading: Notice | null;
}

export const useNoticeStore = create<NoticeStore>()(() => ({ reading: null }));

const set = useNoticeStore.setState;

export const openNotice = (id: string): void => {
  const notice = noticeById(id);
  if (!notice) {
    console.warn(`notice:read named "${id}", which is not in shared/data/notices`);
    return;
  }
  set({ reading: notice });
};

export const closeNotice = (): void => set({ reading: null });

const bridge = installGodotBridge();

bridge.on('notice:read', ({ id }) => openNotice(id));

export const useReading = () => useNoticeStore((s) => s.reading);
