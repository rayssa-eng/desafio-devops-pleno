import http from 'k6/http';
import { sleep } from 'k6';

const token = __ENV.TOKEN;

export let options = {
  vus: 10, // 10 usuários virtuais simultâneos
  duration: '1m', // rodar por 1 minuto
};

export default function () {
  const params = {
    headers: {
      'Host': 'service-1.local',
      'Authorization': `Bearer ${token}`,
    },
  };
  http.get('http://192.168.121.204/status/200', params);
  sleep(0.1); // Pequena pausa para não travar a CPU da VM
}