import { createApp } from 'vue'
import { createRouter, createWebHistory } from 'vue-router'
import App from './App.vue'
import './styles/main.css'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      component: () => import('./pages/Home.vue')
    },
    {
      path: '/guide',
      component: () => import('./pages/Guide.vue')
    },
    {
      path: '/api',
      component: () => import('./pages/Api.vue')
    }
  ]
})

const app = createApp(App)
app.use(router)
app.mount('#app')