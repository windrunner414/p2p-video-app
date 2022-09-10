const webrtcServers = {
  "iceServers": [
    {"url": "stun:stun.l.google.com:19302"},
  ],
};

const offerSdpConstraints = {
  "mandatory": {
    "OfferToReceiveAudio": true,
    "OfferToReceiveVideo": true,
  },
  "optional": [],
};
