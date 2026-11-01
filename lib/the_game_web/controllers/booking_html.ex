defmodule TheGameWeb.BookingHTML do
  use TheGameWeb, :html
  embed_templates "booking_html/*"

  # One place for the words on these pages, so the owner's copy changes in one file.
  @pages %{
    table: %{
      slug: "table",
      title: "Reserve a table",
      short: "1 to 9 guests",
      intro: "Pick a day, a time and how many of you. We confirm by phone or WhatsApp.",
      cta: "Request a table"
    },
    group: %{
      slug: "group",
      title: "Large groups",
      short: "10 or more guests",
      intro:
        "Ten or more. Tell us the plan and we come back with a quote, the minimum spend and any deposit.",
      cta: "Request a group booking"
    },
    event: %{
      slug: "event",
      title: "Events",
      short: "Birthdays, corporate parties, afterparties, graduations",
      intro:
        "Celebrating something? Tell us what and roughly how many, and we shape it with you.",
      cta: "Plan my event"
    },
    collab: %{
      slug: "collab",
      title: "Collabs",
      short: "Brands and creators",
      intro:
        "Brands launching something, creators building content, a night worth doing together. Pitch us.",
      cta: "Send my pitch"
    },
    vip: %{
      slug: "vip",
      title: "VIP experience",
      short: "Reserved, hosted, looked after",
      intro: "The night done properly. Tell us when and who, and a host takes it from there.",
      cta: "Request VIP"
    }
  }

  # What a VIP request gets. Stated as the intent of the offer, not as prices or inventory:
  # staff agree the specifics on the confirmation call.
  def vip_perks,
    do: [
      {"Reserved table", "Held for you. No queueing for a spot."},
      {"A host", "One person looking after your table all night."},
      {"Bottle service", "Ordered ahead, on the table when you arrive."},
      {"Priority", "A fast lane at the door and at the bar."}
    ]

  def page(kind), do: Map.fetch!(@pages, kind)
  def title(kind), do: page(kind).title
  def pages, do: for(k <- [:table, :group, :event, :collab], do: page(k))

  def event_type_label(:birthday), do: "Birthday"
  def event_type_label(:corporate_party), do: "Corporate party"
  def event_type_label(:afterparty), do: "Afterparty"
  def event_type_label(:graduation), do: "Graduation"
  def event_type_label(:other), do: "Something else"

  def vip_label(:reserved_table), do: "A reserved table with a host"
  def vip_label(:bottle_service), do: "Bottle service"
  def vip_label(:advise_me), do: "Not sure yet, advise me"

  def seating_label(:any), do: "Anywhere"
  def seating_label(:indoor), do: "Indoors"
  def seating_label(:outdoor), do: "Outdoors"

  def collab_label(:brand), do: "A brand"
  def collab_label(:creator), do: "A creator"

  def kind_text(:table), do: "table reservation"
  def kind_text(:group), do: "group booking"
  def kind_text(:event), do: "event"
  def kind_text(:collab), do: "collab pitch"
  def kind_text(:vip), do: "VIP request"

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :v, :map, required: true
  attr :errors, :map, required: true
  attr :type, :string, default: "text"
  attr :rest, :global, include: ~w(required min max maxlength inputmode autocomplete placeholder)
  attr :help, :string, default: nil

  def field(assigns) do
    ~H"""
    <div class="bf">
      <label for={"b-" <> @name}>{@label}</label>
      <input
        id={"b-" <> @name}
        name={"booking[" <> @name <> "]"}
        type={@type}
        value={@v[@name]}
        aria-invalid={@errors[@name] && "true"}
        aria-describedby={describedby(@name, @errors, @help)}
        {@rest}
      />
      <.note name={@name} errors={@errors} help={@help} />
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :v, :map, required: true
  attr :errors, :map, required: true
  attr :options, :list, required: true
  attr :blank, :string, default: nil
  attr :required, :boolean, default: false

  def pick(assigns) do
    ~H"""
    <div class="bf">
      <label for={"b-" <> @name}>{@label}</label>
      <select
        id={"b-" <> @name}
        name={"booking[" <> @name <> "]"}
        required={@required}
        aria-invalid={@errors[@name] && "true"}
        aria-describedby={describedby(@name, @errors, nil)}
      >
        <option :if={@blank} value="">{@blank}</option>
        <option :for={{value, text} <- @options} value={value} selected={@v[@name] == value}>
          {text}
        </option>
      </select>
      <.note name={@name} errors={@errors} help={nil} />
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :v, :map, required: true
  attr :errors, :map, required: true
  attr :help, :string, default: nil
  attr :rows, :integer, default: 4

  def area(assigns) do
    ~H"""
    <div class="bf">
      <label for={"b-" <> @name}>{@label}</label>
      <textarea
        id={"b-" <> @name}
        name={"booking[" <> @name <> "]"}
        rows={@rows}
        maxlength="1500"
        aria-invalid={@errors[@name] && "true"}
        aria-describedby={describedby(@name, @errors, @help)}
      >{@v[@name]}</textarea>
      <.note name={@name} errors={@errors} help={@help} />
    </div>
    """
  end

  defp note(assigns) do
    ~H"""
    <p :if={@errors[@name]} id={"e-" <> @name} class="err" role="alert">{@errors[@name]}</p>
    <p :if={@help && !@errors[@name]} id={"e-" <> @name} class="help">{@help}</p>
    """
  end

  defp describedby(name, errors, help), do: if(errors[name] || help, do: "e-" <> name)

  def options(values, labeler), do: for(v <- values, do: {Atom.to_string(v), labeler.(v)})
end
