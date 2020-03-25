from django.utils.translation import ugettext_lazy as _

from ralph.access_cards.models import AccessCard, AccessZone
from ralph.admin import RalphAdmin, RalphMPTTAdmin, register
from ralph.lib.transitions.admin import TransitionAdminMixin


@register(AccessCard)
class AccessCardAdmin(TransitionAdminMixin, RalphAdmin):
    show_transition_history = True
    list_display = ['status', 'visual_number', 'system_number', 'user',
                    'owner', 'get_employee_id']
    list_select_related = ['user', 'owner']
    raw_id_fields = ['user', 'owner', 'region']
    list_filter = ['status', 'issue_date', 'visual_number',
                   'system_number', 'user', 'owner', 'user__segment',
                   'user__company', 'user__department', 'user__employee_id',
                   'access_zones', 'notes']
    search_fields = ['visual_number', 'system_number', 'user__first_name',
                     'user__last_name', 'user__username']

    fieldsets = (
        (
            _('Access Card Info'),
            {
                'fields': ('visual_number', 'system_number',
                           'status', 'region', 'issue_date', 'notes')
            }
        ),
        (
            _('User Info'),
            {
                'fields': ('user', 'owner')
            }
        ),
        (
            _('Access Zones'),
            {
                'fields': ('access_zones',)
            }
        ),

    )

    def get_employee_id(self, obj):
        if obj.user is not None:
            return obj.user.employee_id,


@register(AccessZone)
class AccessZoneAdmin(RalphMPTTAdmin):
    list_display = ['name', 'parent', 'description']
    search_fields = ['name', 'description']

    fieldsets = (
        (
            _('Access Zone'),
            {
                'fields': ('parent', 'name', 'description')
            }
        ),
    )
