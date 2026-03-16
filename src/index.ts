import { registerPlugin } from '@capacitor/core';

export interface YoutubePlayerPlugin {
  play(options: { videoId: string }): Promise<{ status: string }>;
}

const YoutubePlayer = registerPlugin<YoutubePlayerPlugin>('YoutubePlayer', {
  web: () => import('./web').then(m => new m.YoutubePlayerWeb()),
});

export { YoutubePlayer };