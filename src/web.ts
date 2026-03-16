import { WebPlugin } from '@capacitor/core';

import type { YoutubePlayerPlugin } from './index';
import type { PlayOptions } from './interface';

export class YoutubePlayerWeb extends WebPlugin implements YoutubePlayerPlugin {

  async play(options: PlayOptions): Promise<any> {

    console.log("YoutubePlayerWeb play called", options);

    console.warn("Youtube player not supported on web");

    return {
      status: "web fallback"
    };
  }

}